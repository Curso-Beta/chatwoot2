/* global axios */
import ApiClient from './ApiClient';

class AgentAvailabilityAPI extends ApiClient {
  constructor() {
    super('agent_availability', { accountScoped: true });
  }

  history(days = 1) {
    return axios.get(`${this.url}/history`, { params: { days } });
  }
}

export default new AgentAvailabilityAPI();
