import { isExcludedURL, resolveBubbleVisibility } from '../excludedPaths';

describe('#isExcludedURL', () => {
  const url =
    'https://admin.hotwebinar.com.br/dashboard/sala-de-atendimento/1/2';

  it('returns true when the URL contains an excluded path', () => {
    expect(isExcludedURL(['sala-de-atendimento'], url)).toEqual(true);
  });

  it('returns false when no path matches', () => {
    expect(isExcludedURL(['checkout'], url)).toEqual(false);
  });

  it('returns false for empty or missing paths', () => {
    expect(isExcludedURL([], url)).toEqual(false);
    expect(isExcludedURL(undefined, url)).toEqual(false);
    expect(isExcludedURL([''], url)).toEqual(false);
  });
});

describe('#resolveBubbleVisibility', () => {
  it('keeps the bubble hidden on excluded URLs even when show is requested', () => {
    expect(
      resolveBubbleVisibility({ requested: 'show', excluded: true })
    ).toEqual('hide');
  });

  it('follows the requested visibility outside excluded URLs', () => {
    expect(
      resolveBubbleVisibility({ requested: 'show', excluded: false })
    ).toEqual('show');
    expect(
      resolveBubbleVisibility({ requested: 'hide', excluded: false })
    ).toEqual('hide');
  });
});
