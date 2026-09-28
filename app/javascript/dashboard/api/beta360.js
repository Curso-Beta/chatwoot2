import ApiClient from './ApiClient';

class Beta360API extends ApiClient {
  constructor() {
    super('beta360', { accountScoped: true, apiVersion: 'v2' });
  }

  getMetrics({ since, until: untilDate }) {
    return axios.get(this.url, {
      params: { since, until: untilDate },
    });
  }
}

export default new Beta360API();
