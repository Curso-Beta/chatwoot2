<template>
  <div class="flex flex-col h-full overflow-auto bg-n-background">
    <header class="flex items-center justify-between px-6 py-4 border-b border-n-weak">
      <h1 class="text-2xl font-bold text-n-slate-12">360 Beta</h1>
      <div class="flex gap-2">
        <button
          v-for="option in periodOptions"
          :key="option.value"
          class="px-3 py-1.5 text-sm rounded-lg transition-colors"
          :class="selectedPeriod === option.value
            ? 'bg-n-brand text-white'
            : 'bg-n-alpha-2 text-n-slate-11 hover:bg-n-alpha-3'"
          @click="changePeriod(option.value)"
        >
          {{ option.label }}
        </button>
      </div>
    </header>

    <div v-if="loading" class="flex items-center justify-center flex-1">
      <span class="text-n-slate-11">Carregando...</span>
    </div>

    <div v-else class="flex-1 p-6 space-y-6">
      <!-- KPI Cards -->
      <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <div
          v-for="kpi in kpiCards"
          :key="kpi.label"
          class="p-4 rounded-xl border border-n-weak bg-n-solid-2"
        >
          <p class="text-xs font-medium uppercase tracking-wide text-n-slate-10">
            {{ kpi.label }}
          </p>
          <p class="mt-1 text-2xl font-bold text-n-slate-12">
            {{ kpi.value }}
          </p>
          <p v-if="kpi.sub" class="mt-0.5 text-xs text-n-slate-10">
            {{ kpi.sub }}
          </p>
        </div>
      </div>

      <!-- AI Section -->
      <section>
        <h2 class="mb-3 text-lg font-semibold text-n-slate-12">
          Atendimento IA
        </h2>
        <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <div
            v-for="card in aiCards"
            :key="card.label"
            class="p-4 rounded-xl border border-n-weak bg-n-solid-2"
          >
            <p class="text-xs font-medium uppercase tracking-wide text-n-slate-10">
              {{ card.label }}
            </p>
            <p class="mt-1 text-2xl font-bold text-n-slate-12">
              {{ card.value }}
            </p>
          </div>
        </div>
      </section>

      <!-- Teams Section -->
      <section>
        <h2 class="mb-3 text-lg font-semibold text-n-slate-12">
          Times
        </h2>
        <div class="overflow-hidden rounded-xl border border-n-weak">
          <table class="w-full text-sm">
            <thead>
              <tr class="bg-n-alpha-2">
                <th class="px-4 py-3 text-left font-medium text-n-slate-11">Time</th>
                <th class="px-4 py-3 text-right font-medium text-n-slate-11">Total</th>
                <th class="px-4 py-3 text-right font-medium text-n-slate-11">Resolvidas</th>
                <th class="px-4 py-3 text-right font-medium text-n-slate-11">Abertas</th>
                <th class="px-4 py-3 text-right font-medium text-n-slate-11">Pendentes</th>
                <th class="px-4 py-3 text-right font-medium text-n-slate-11">Taxa Resolução</th>
                <th class="px-4 py-3 text-right font-medium text-n-slate-11">Tempo Resp.</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="team in teams"
                :key="team.id"
                class="border-t border-n-weak"
              >
                <td class="px-4 py-3 font-medium text-n-slate-12">{{ team.name }}</td>
                <td class="px-4 py-3 text-right text-n-slate-11">{{ team.total }}</td>
                <td class="px-4 py-3 text-right text-n-slate-11">{{ team.resolved }}</td>
                <td class="px-4 py-3 text-right text-n-slate-11">{{ team.open }}</td>
                <td class="px-4 py-3 text-right text-n-slate-11">{{ team.pending }}</td>
                <td class="px-4 py-3 text-right font-medium" :class="rateColor(team.resolution_rate)">
                  {{ team.resolution_rate }}%
                </td>
                <td class="px-4 py-3 text-right text-n-slate-11">
                  {{ formatDuration(team.avg_first_response_time) }}
                </td>
              </tr>
              <tr v-if="!teams.length" class="border-t border-n-weak">
                <td colspan="7" class="px-4 py-6 text-center text-n-slate-10">
                  Nenhum time configurado
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Timeline -->
      <section v-if="timeline.length">
        <h2 class="mb-3 text-lg font-semibold text-n-slate-12">
          Conversas por Dia
        </h2>
        <div class="p-4 rounded-xl border border-n-weak bg-n-solid-2">
          <div class="flex items-end gap-1 h-32">
            <div
              v-for="day in timeline"
              :key="day.date"
              class="flex-1 bg-n-brand rounded-t transition-all hover:opacity-80"
              :style="{ height: barHeight(day.count) + '%' }"
              :title="`${day.date}: ${day.count} conversas`"
            />
          </div>
          <div class="flex justify-between mt-2 text-xs text-n-slate-10">
            <span>{{ timeline[0]?.date }}</span>
            <span>{{ timeline[timeline.length - 1]?.date }}</span>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>

<script>
import { useAccount } from 'dashboard/composables/useAccount';

export default {
  name: 'Beta360Dashboard',
  setup() {
    const { accountId } = useAccount();
    return { accountId };
  },
  data() {
    return {
      loading: true,
      selectedPeriod: 30,
      overview: {},
      teams: [],
      ai: {},
      timeline: [],
      periodOptions: [
        { label: '7 dias', value: 7 },
        { label: '30 dias', value: 30 },
        { label: '90 dias', value: 90 },
      ],
    };
  },
  computed: {
    kpiCards() {
      return [
        {
          label: 'Conversas',
          value: this.overview.total_conversations ?? '—',
          sub: `${this.overview.open_conversations ?? 0} abertas`,
        },
        {
          label: 'Resolvidas',
          value: this.overview.resolved_conversations ?? '—',
          sub: `${this.overview.resolution_rate ?? 0}% taxa`,
        },
        {
          label: 'Tempo Primeira Resposta',
          value: this.formatDuration(this.overview.avg_first_response_time),
          sub: 'média',
        },
        {
          label: 'CSAT',
          value: this.overview.csat_avg ? `${this.overview.csat_avg}/5` : '—',
          sub: this.overview.csat_count
            ? `${this.overview.csat_count} respostas`
            : 'sem dados',
        },
      ];
    },
    aiCards() {
      return [
        { label: 'Mensagens do Bot', value: this.ai.bot_messages ?? '—' },
        { label: 'Conversas com IA', value: this.ai.bot_conversations ?? '—' },
        { label: 'Mensagens Humanas', value: this.ai.human_messages ?? '—' },
        { label: 'Mensagens Recebidas', value: this.ai.incoming_messages ?? '—' },
      ];
    },
    maxTimelineCount() {
      return Math.max(...this.timeline.map(d => d.count), 1);
    },
  },
  mounted() {
    this.fetchData();
  },
  methods: {
    async fetchData() {
      this.loading = true;
      try {
        const since = new Date();
        since.setDate(since.getDate() - this.selectedPeriod);

        const response = await axios.get(
          `/api/v2/accounts/${this.accountId}/beta360`,
          {
            params: {
              since: since.toISOString().split('T')[0],
              until: new Date().toISOString().split('T')[0],
            },
          }
        );

        const data = response.data;
        this.overview = data.overview || {};
        this.teams = data.teams || [];
        this.ai = data.ai || {};
        this.timeline = data.timeline || [];
      } catch (error) {
        console.error('[360 Beta] Failed to load metrics:', error);
      } finally {
        this.loading = false;
      }
    },
    changePeriod(days) {
      this.selectedPeriod = days;
      this.fetchData();
    },
    formatDuration(seconds) {
      if (!seconds) return '—';
      if (seconds < 60) return `${seconds}s`;
      if (seconds < 3600) return `${Math.round(seconds / 60)}min`;
      const hours = Math.floor(seconds / 3600);
      const mins = Math.round((seconds % 3600) / 60);
      return `${hours}h ${mins}min`;
    },
    rateColor(rate) {
      if (rate >= 70) return 'text-green-600 dark:text-green-400';
      if (rate >= 40) return 'text-yellow-600 dark:text-yellow-400';
      return 'text-red-600 dark:text-red-400';
    },
    barHeight(count) {
      return Math.max((count / this.maxTimelineCount) * 100, 2);
    },
  },
};
</script>
