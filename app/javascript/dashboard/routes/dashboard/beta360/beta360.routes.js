import { frontendURL } from '../../../helper/URLHelper';

const Beta360Dashboard = () => import('./Index.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/beta360'),
    name: 'beta360_dashboard',
    meta: {
      permissions: ['administrator', 'agent', 'custom_role'],
    },
    component: Beta360Dashboard,
  },
];
