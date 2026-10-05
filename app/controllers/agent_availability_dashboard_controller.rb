class AgentAvailabilityDashboardController < ActionController::Base
  before_action :authenticate_user
  before_action :set_account

  def show
    render html: dashboard_html.html_safe, layout: false
  end

  private

  def authenticate_user
    @current_user = current_user
    redirect_to '/auth/sign_in' unless @current_user
  end

  def current_user
    @current_user ||= if warden&.authenticated?(:user)
                         warden.user(:user)
                       end
  end

  def warden
    request.env['warden']
  end

  def set_account
    @account = @current_user.accounts.find_by(id: params[:account_id])
    render plain: 'Conta não encontrada', status: :not_found unless @account
  end

  def dashboard_html # rubocop:disable Metrics/MethodLength
    account_id = @account.id
    <<~HTML
      <!DOCTYPE html>
      <html lang="pt-BR">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Disponibilidade dos Agentes</title>
        <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js"></script>
        <style>
          :root {
            --bg: #f8f9fa;
            --bg-card: #ffffff;
            --fg: #1b1b1b;
            --fg-muted: #6b7280;
            --border: #e5e7eb;
            --online: #22c55e;
            --busy: #f59e0b;
            --offline: #94a3b8;
            --accent: #3b82f6;
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --bg: #111827;
              --bg-card: #1f2937;
              --fg: #f3f4f6;
              --fg-muted: #9ca3af;
              --border: #374151;
              --online: #4ade80;
              --busy: #fbbf24;
              --offline: #64748b;
              --accent: #60a5fa;
            }
          }
          * { margin:0; padding:0; box-sizing:border-box; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg);
            color: var(--fg);
            padding: 16px;
            line-height: 1.5;
          }
          h1 { font-size: 1.25rem; font-weight: 600; margin-bottom: 16px; }
          h2 { font-size: 1rem; font-weight: 600; margin: 20px 0 10px; color: var(--fg); }
          .cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; margin-bottom: 20px; }
          .card {
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 14px;
            display: flex;
            align-items: center;
            gap: 10px;
          }
          .avatar {
            width: 36px; height: 36px;
            border-radius: 50%;
            background: var(--accent);
            color: white;
            display: flex; align-items: center; justify-content: center;
            font-weight: 600; font-size: 0.85rem;
            flex-shrink: 0;
          }
          .avatar img { width: 100%; height: 100%; border-radius: 50%; object-fit: cover; }
          .agent-info { flex: 1; min-width: 0; }
          .agent-name { font-weight: 500; font-size: 0.9rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
          .agent-role { font-size: 0.75rem; color: var(--fg-muted); }
          .status-dot {
            width: 10px; height: 10px;
            border-radius: 50%;
            flex-shrink: 0;
          }
          .status-dot.online { background: var(--online); }
          .status-dot.busy { background: var(--busy); }
          .status-dot.offline { background: var(--offline); }
          .summary-cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 10px; margin-bottom: 20px; }
          .summary-card {
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 12px;
            text-align: center;
          }
          .summary-card .value { font-size: 1.5rem; font-weight: 700; }
          .summary-card .label { font-size: 0.75rem; color: var(--fg-muted); }
          .chart-container {
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 16px;
            margin-bottom: 20px;
            max-height: 300px;
          }
          table {
            width: 100%;
            border-collapse: collapse;
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 8px;
            overflow: hidden;
            font-size: 0.85rem;
          }
          th, td { padding: 8px 12px; text-align: left; border-bottom: 1px solid var(--border); }
          th { background: var(--bg); font-weight: 600; font-size: 0.75rem; text-transform: uppercase; color: var(--fg-muted); }
          .badge {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 9999px;
            font-size: 0.75rem;
            font-weight: 500;
          }
          .badge.online { background: #dcfce7; color: #166534; }
          .badge.busy { background: #fef3c7; color: #92400e; }
          .badge.offline { background: #f1f5f9; color: #475569; }
          @media (prefers-color-scheme: dark) {
            .badge.online { background: #166534; color: #dcfce7; }
            .badge.busy { background: #92400e; color: #fef3c7; }
            .badge.offline { background: #334155; color: #cbd5e1; }
          }
          .timeline { margin-bottom: 20px; overflow-x: auto; }
          .timeline-row { display: flex; align-items: center; margin-bottom: 6px; gap: 8px; }
          .timeline-label { width: 100px; font-size: 0.8rem; font-weight: 500; flex-shrink: 0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
          .timeline-bar { flex: 1; height: 20px; position: relative; border-radius: 4px; overflow: hidden; min-width: 200px; background: var(--border); }
          .timeline-segment { height: 100%; position: absolute; top: 0; }
          .timeline-segment:hover::after {
            content: attr(data-tip);
            position: absolute;
            bottom: 24px; left: 50%;
            transform: translateX(-50%);
            background: var(--fg);
            color: var(--bg);
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 0.7rem;
            white-space: nowrap;
            z-index: 10;
          }
          .tabs { display: flex; gap: 4px; margin-bottom: 16px; flex-wrap: wrap; }
          .tab {
            padding: 6px 14px;
            border: 1px solid var(--border);
            border-radius: 6px;
            background: var(--bg-card);
            cursor: pointer;
            font-size: 0.85rem;
            color: var(--fg);
          }
          .tab.active { background: var(--accent); color: white; border-color: var(--accent); }
          .period-select {
            float: right;
            padding: 4px 8px;
            border: 1px solid var(--border);
            border-radius: 6px;
            background: var(--bg-card);
            color: var(--fg);
            font-size: 0.8rem;
          }
          .loading { text-align: center; padding: 40px; color: var(--fg-muted); }
          @media (max-width: 600px) {
            .cards { grid-template-columns: 1fr; }
            .summary-cards { grid-template-columns: repeat(2, 1fr); }
          }
        </style>
      </head>
      <body>
        <div style="display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 8px; margin-bottom: 16px;">
          <h1>Disponibilidade dos Agentes</h1>
          <select class="period-select" id="periodSelect" onchange="loadData()">
            <option value="1">Hoje</option>
            <option value="7" selected>7 dias</option>
            <option value="14">14 dias</option>
            <option value="30">30 dias</option>
          </select>
        </div>

        <div class="tabs" id="viewTabs">
          <button class="tab active" data-view="live" onclick="switchView('live')">Ao vivo</button>
          <button class="tab" data-view="summary" onclick="switchView('summary')">Resumo</button>
          <button class="tab" data-view="timeline" onclick="switchView('timeline')">Timeline</button>
          <button class="tab" data-view="sessions" onclick="switchView('sessions')">Sessões</button>
        </div>

        <div id="liveView"><div class="loading">Carregando...</div></div>
        <div id="summaryView" style="display:none"></div>
        <div id="timelineView" style="display:none"></div>
        <div id="sessionsView" style="display:none"></div>

        <script>
          const ACCOUNT_ID = #{account_id};
          const API_BASE = '/api/v1/accounts/' + ACCOUNT_ID + '/agent_availability';
          let currentView = 'live';
          let chartInstance = null;

          function getHeaders() {
            const meta = document.querySelector('meta[name="csrf-token"]');
            return {
              'Content-Type': 'application/json',
              ...(meta ? {'X-CSRF-Token': meta.content} : {})
            };
          }

          async function apiFetch(endpoint, params = {}) {
            const qs = new URLSearchParams(params).toString();
            const url = API_BASE + '/' + endpoint + (qs ? '?' + qs : '');
            const res = await fetch(url, { credentials: 'same-origin', headers: getHeaders() });
            if (!res.ok) throw new Error('HTTP ' + res.status);
            return res.json();
          }

          function switchView(view) {
            currentView = view;
            document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.view === view));
            ['liveView','summaryView','timelineView','sessionsView'].forEach(id => {
              document.getElementById(id).style.display = 'none';
            });
            document.getElementById(view + 'View').style.display = '';
            loadData();
          }

          function initials(name) {
            return name.split(' ').slice(0,2).map(w => w[0]).join('').toUpperCase();
          }

          function formatDuration(min) {
            if (!min && min !== 0) return '—';
            if (min < 60) return Math.round(min) + 'min';
            const h = Math.floor(min / 60);
            const m = Math.round(min % 60);
            return h + 'h' + (m > 0 ? m + 'min' : '');
          }

          function formatTime(iso) {
            if (!iso) return '—';
            return new Date(iso).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', day:'2-digit', month:'2-digit', hour:'2-digit', minute:'2-digit' });
          }

          async function loadLive() {
            try {
              const agents = await apiFetch('live');
              const online = agents.filter(a => a.availability === 'online').length;
              const busy = agents.filter(a => a.availability === 'busy').length;
              const offline = agents.filter(a => a.availability === 'offline').length;

              let html = '<div class="summary-cards">';
              html += '<div class="summary-card"><div class="value" style="color:var(--online)">' + online + '</div><div class="label">Online</div></div>';
              html += '<div class="summary-card"><div class="value" style="color:var(--busy)">' + busy + '</div><div class="label">Ocupado</div></div>';
              html += '<div class="summary-card"><div class="value" style="color:var(--offline)">' + offline + '</div><div class="label">Offline</div></div>';
              html += '<div class="summary-card"><div class="value">' + agents.length + '</div><div class="label">Total</div></div>';
              html += '</div>';

              html += '<div class="cards">';
              agents.sort((a,b) => {
                const order = {online:0, busy:1, offline:2};
                return (order[a.availability]||9) - (order[b.availability]||9);
              });
              for (const a of agents) {
                const av = '<img src="' + (a.avatar_url || '') + '" onerror="this.style.display=\\'none\\';this.parentNode.textContent=\\'' + initials(a.name) + '\\';">';
                html += '<div class="card">';
                html += '<div class="avatar">' + av + '</div>';
                html += '<div class="agent-info"><div class="agent-name">' + a.name + '</div><div class="agent-role">' + (a.role === 'administrator' ? 'Admin' : 'Agente') + '</div></div>';
                html += '<div class="status-dot ' + a.availability + '" title="' + a.availability + '"></div>';
                html += '</div>';
              }
              html += '</div>';
              document.getElementById('liveView').innerHTML = html;
            } catch(e) {
              document.getElementById('liveView').innerHTML = '<div class="loading">Erro ao carregar: ' + e.message + '</div>';
            }
          }

          async function loadSummary() {
            try {
              const days = document.getElementById('periodSelect').value;
              const data = await apiFetch('summary', { days });
              let html = '<div class="cards">';
              for (const [name, totals] of Object.entries(data)) {
                html += '<div class="card" style="flex-direction:column; align-items:flex-start; gap:6px;">';
                html += '<div class="agent-name">' + name + '</div>';
                html += '<div style="font-size:0.8rem"><span style="color:var(--online)">● Online: ' + formatDuration(totals.online) + '</span></div>';
                html += '<div style="font-size:0.8rem"><span style="color:var(--busy)">● Ocupado: ' + formatDuration(totals.busy) + '</span></div>';
                html += '<div style="font-size:0.8rem"><span style="color:var(--offline)">● Offline: ' + formatDuration(totals.offline) + '</span></div>';
                html += '</div>';
              }
              if (!Object.keys(data).length) html += '<div class="loading">Sem dados no período</div>';
              html += '</div>';

              html += '<h2>Horas por Agente</h2>';
              html += '<div class="chart-container"><canvas id="summaryChart"></canvas></div>';
              document.getElementById('summaryView').innerHTML = html;

              const agents = Object.keys(data);
              if (agents.length) {
                const ctx = document.getElementById('summaryChart').getContext('2d');
                if (chartInstance) chartInstance.destroy();
                const fg = getComputedStyle(document.body).getPropertyValue('--fg').trim();
                chartInstance = new Chart(ctx, {
                  type: 'bar',
                  data: {
                    labels: agents,
                    datasets: [
                      { label: 'Online', data: agents.map(a => +(data[a].online/60).toFixed(1)), backgroundColor: '#22c55e' },
                      { label: 'Ocupado', data: agents.map(a => +(data[a].busy/60).toFixed(1)), backgroundColor: '#f59e0b' },
                      { label: 'Offline', data: agents.map(a => +(data[a].offline/60).toFixed(1)), backgroundColor: '#94a3b8' }
                    ]
                  },
                  options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                      x: { stacked: true, ticks: { color: fg } },
                      y: { stacked: true, title: { display: true, text: 'Horas', color: fg }, ticks: { color: fg } }
                    },
                    plugins: { legend: { labels: { color: fg } } }
                  }
                });
              }
            } catch(e) {
              document.getElementById('summaryView').innerHTML = '<div class="loading">Erro: ' + e.message + '</div>';
            }
          }

          async function loadTimeline() {
            try {
              const days = document.getElementById('periodSelect').value;
              const sessions = await apiFetch('sessions', { days });
              const grouped = {};
              for (const s of sessions) {
                if (!grouped[s.agent_name]) grouped[s.agent_name] = [];
                grouped[s.agent_name].push(s);
              }

              let html = '<div class="timeline">';
              const now = Date.now();
              const rangeMs = days * 86400000;
              const rangeStart = now - rangeMs;

              for (const [name, segs] of Object.entries(grouped)) {
                html += '<div class="timeline-row">';
                html += '<div class="timeline-label" title="' + name + '">' + name + '</div>';
                html += '<div class="timeline-bar">';
                const sorted = segs.sort((a,b) => new Date(a.started_at) - new Date(b.started_at));
                for (const s of sorted) {
                  const start = Math.max(new Date(s.started_at).getTime(), rangeStart);
                  const end = s.ended_at ? new Date(s.ended_at).getTime() : now;
                  const left = ((start - rangeStart) / rangeMs * 100).toFixed(2);
                  const width = Math.max(((end - start) / rangeMs * 100), 0.3).toFixed(2);
                  const colors = { online: 'var(--online)', busy: 'var(--busy)', offline: 'var(--offline)' };
                  const tip = s.availability + ' — ' + formatTime(s.started_at) + ' a ' + (s.ended_at ? formatTime(s.ended_at) : 'agora');
                  html += '<div class="timeline-segment" style="left:' + left + '%;width:' + width + '%;background:' + (colors[s.availability]||'gray') + '" data-tip="' + tip + '"></div>';
                }
                html += '</div></div>';
              }
              if (!Object.keys(grouped).length) html += '<div class="loading">Sem dados no período</div>';
              html += '</div>';
              document.getElementById('timelineView').innerHTML = html;
            } catch(e) {
              document.getElementById('timelineView').innerHTML = '<div class="loading">Erro: ' + e.message + '</div>';
            }
          }

          async function loadSessions() {
            try {
              const days = document.getElementById('periodSelect').value;
              const sessions = await apiFetch('sessions', { days });
              let html = '<table><thead><tr><th>Agente</th><th>Status</th><th>Início</th><th>Fim</th><th>Duração</th></tr></thead><tbody>';
              for (const s of sessions.slice(0, 200)) {
                html += '<tr>';
                html += '<td>' + s.agent_name + '</td>';
                html += '<td><span class="badge ' + s.availability + '">' + s.availability + '</span></td>';
                html += '<td>' + formatTime(s.started_at) + '</td>';
                html += '<td>' + (s.ended_at ? formatTime(s.ended_at) : '<em>agora</em>') + '</td>';
                html += '<td>' + formatDuration(s.duration_minutes) + '</td>';
                html += '</tr>';
              }
              if (!sessions.length) html += '<tr><td colspan="5" style="text-align:center">Sem dados no período</td></tr>';
              html += '</tbody></table>';
              document.getElementById('sessionsView').innerHTML = html;
            } catch(e) {
              document.getElementById('sessionsView').innerHTML = '<div class="loading">Erro: ' + e.message + '</div>';
            }
          }

          function loadData() {
            if (currentView === 'live') loadLive();
            else if (currentView === 'summary') loadSummary();
            else if (currentView === 'timeline') loadTimeline();
            else if (currentView === 'sessions') loadSessions();
          }

          loadData();
          setInterval(() => { if (currentView === 'live') loadLive(); }, 30000);
        </script>
      </body>
      </html>
    HTML
  end
end
