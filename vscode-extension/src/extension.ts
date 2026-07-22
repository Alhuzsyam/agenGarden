// AgentGarden — VS Code client for the AgentGarden server. Makes VS Code a
// fourth approval surface (alongside phone / Garmin / webapp): shows the live
// agent fleet + pending approvals, pops a notification to Approve/Deny, and
// registers the current workspace as an agent. It talks to the same HTTP server
// as everything else — no Copilot/agent internals are touched.
import * as vscode from 'vscode';
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

function cfg() { return vscode.workspace.getConfiguration('agentgarden'); }

function serverUrl(): string {
  return (cfg().get<string>('serverUrl') || 'http://127.0.0.1:4141').replace(/\/+$/, '');
}

function getToken(): string {
  const t = cfg().get<string>('token');
  if (t && t.trim()) { return t.trim(); }
  try {
    return fs.readFileSync(path.join(os.homedir(), '.agent-garden-token'), 'utf8').trim();
  } catch { return ''; }
}

async function api(pathname: string, method = 'GET', body?: unknown): Promise<any> {
  const headers: Record<string, string> = { Authorization: `Bearer ${getToken()}` };
  if (body !== undefined) { headers['Content-Type'] = 'application/json'; }
  const res = await fetch(serverUrl() + pathname, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  try { return JSON.parse(text); } catch { return text; }
}

interface Agent {
  id: string;
  needsAttention?: boolean;
  isDone?: boolean;
  isError?: boolean;
  lastTool?: string;
  task?: string;
}
interface Approval { id: string; agent: string; tool: string; detail: string; }

let status: vscode.StatusBarItem;
let provider: FleetProvider;
const seenApprovals = new Set<string>();
let timer: ReturnType<typeof setInterval> | undefined;

class FleetProvider implements vscode.TreeDataProvider<vscode.TreeItem> {
  private _onDidChange = new vscode.EventEmitter<void>();
  readonly onDidChangeTreeData = this._onDidChange.event;
  agents: Agent[] = [];
  approvals: Approval[] = [];

  refresh() { this._onDidChange.fire(); }
  getTreeItem(el: vscode.TreeItem) { return el; }

  getChildren(el?: vscode.TreeItem): vscode.TreeItem[] {
    if (el) { return []; }
    const items: vscode.TreeItem[] = [];
    for (const ap of this.approvals) {
      const it = new vscode.TreeItem(`${ap.agent}: ${ap.detail}`, vscode.TreeItemCollapsibleState.None);
      it.description = ap.tool;
      it.iconPath = new vscode.ThemeIcon('warning', new vscode.ThemeColor('list.warningForeground'));
      it.command = { command: 'agentgarden.decide', title: 'Decide', arguments: [ap] };
      it.contextValue = 'approval';
      items.push(it);
    }
    for (const a of this.agents) {
      const it = new vscode.TreeItem(a.id, vscode.TreeItemCollapsibleState.None);
      it.description = a.needsAttention ? 'blocked'
        : a.isError ? 'error'
        : a.isDone ? 'done'
        : (a.lastTool || 'running');
      it.iconPath = new vscode.ThemeIcon(
        a.isError ? 'error' : a.needsAttention ? 'warning' : a.isDone ? 'pass' : 'loading~spin');
      items.push(it);
    }
    if (items.length === 0) {
      items.push(new vscode.TreeItem('No agents running', vscode.TreeItemCollapsibleState.None));
    }
    return items;
  }
}

async function decide(ap: Approval, decision: 'allow' | 'deny') {
  try {
    await api(`/approval/${ap.id}/decide`, 'POST', { decision });
    vscode.window.setStatusBarMessage(`AgentGarden: ${decision === 'allow' ? 'approved' : 'denied'} ${ap.agent}`, 3000);
    poll();
  } catch (e) {
    vscode.window.showErrorMessage(`AgentGarden: ${e}`);
  }
}

async function notifyApproval(ap: Approval) {
  const pick = await vscode.window.showWarningMessage(
    `${ap.agent} wants to run ${ap.tool}: ${ap.detail}`,
    'Approve', 'Deny');
  if (pick === 'Approve') { await decide(ap, 'allow'); }
  else if (pick === 'Deny') { await decide(ap, 'deny'); }
}

async function poll() {
  try {
    const [agents, approvals] = await Promise.all([api('/agents'), api('/approvals')]);
    provider.agents = Array.isArray(agents) ? agents : [];
    provider.approvals = Array.isArray(approvals) ? approvals : [];
    provider.refresh();

    const pending = provider.approvals.length;
    const running = provider.agents.length;
    status.text = pending > 0 ? `$(warning) AgentGarden: ${pending} pending` : `$(hubot) AgentGarden: ${running}`;
    status.backgroundColor = pending > 0 ? new vscode.ThemeColor('statusBarItem.warningBackground') : undefined;
    status.tooltip = `${running} agent(s) · ${pending} pending approval(s) — click to open dashboard`;
    status.show();

    const currentIds = new Set(provider.approvals.map(a => a.id));
    for (const ap of provider.approvals) {
      if (!seenApprovals.has(ap.id)) {
        seenApprovals.add(ap.id);
        notifyApproval(ap);
      }
    }
    for (const id of Array.from(seenApprovals)) {
      if (!currentIds.has(id)) { seenApprovals.delete(id); }
    }
  } catch (e) {
    status.text = '$(error) AgentGarden: offline';
    status.backgroundColor = undefined;
    status.tooltip = `Can't reach ${serverUrl()} — ${e}`;
    status.show();
  }
}

export function activate(ctx: vscode.ExtensionContext) {
  status = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  status.command = 'agentgarden.openDashboard';
  ctx.subscriptions.push(status);

  provider = new FleetProvider();
  ctx.subscriptions.push(vscode.window.registerTreeDataProvider('agentgarden.fleet', provider));

  ctx.subscriptions.push(
    vscode.commands.registerCommand('agentgarden.decide', async (ap?: Approval) => {
      if (!ap) {
        if (provider.approvals.length === 0) {
          vscode.window.showInformationMessage('AgentGarden: no pending approvals.');
          return;
        }
        ap = provider.approvals[0];
      }
      const pick = await vscode.window.showQuickPick(['Approve', 'Deny'], {
        placeHolder: `${ap.agent} · ${ap.tool}: ${ap.detail}`,
      });
      if (pick === 'Approve') { await decide(ap, 'allow'); }
      else if (pick === 'Deny') { await decide(ap, 'deny'); }
    }),
    vscode.commands.registerCommand('agentgarden.openDashboard', () => {
      vscode.env.openExternal(vscode.Uri.parse(`${serverUrl()}/?token=${encodeURIComponent(getToken())}`));
    }),
    vscode.commands.registerCommand('agentgarden.newProject', async () => {
      const name = await vscode.window.showInputBox({ prompt: 'New project name', placeHolder: 'api-refactor' });
      if (!name) { return; }
      const dir = await vscode.window.showInputBox({ prompt: 'Folder (optional — default ~/name)', placeHolder: '' });
      const r = await api('/new-project', 'POST', { name, dir: dir || null });
      if (r && r.ok) { vscode.window.showInformationMessage(`AgentGarden: started ${name}`); }
      else { vscode.window.showErrorMessage(`AgentGarden: ${(r && r.error) || 'new-project failed'}`); }
      poll();
    }),
    vscode.commands.registerCommand('agentgarden.refresh', poll),
  );

  if (cfg().get<boolean>('registerWorkspace')) {
    const ws = vscode.workspace.workspaceFolders?.[0];
    if (ws) {
      const agent = ws.name;
      api('/event', 'POST', { agent, event: 'start', task: ws.uri.fsPath }).catch(() => {});
      ctx.subscriptions.push({
        dispose: () => { api('/event', 'POST', { agent, event: 'done' }).catch(() => {}); },
      });
    }
  }

  poll();
  timer = setInterval(poll, 2500);
  ctx.subscriptions.push({ dispose: () => { if (timer) { clearInterval(timer); } } });
}

export function deactivate() {
  if (timer) { clearInterval(timer); }
}
