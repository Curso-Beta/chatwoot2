export const isExcludedURL = (excludedPaths, url) => {
  if (!Array.isArray(excludedPaths) || !excludedPaths.length || !url) {
    return false;
  }
  return excludedPaths.some(path => path && url.includes(path));
};

// The site may ask to show the bubble at any time (e.g. on chatwoot:ready);
// an excluded URL always wins over that request.
export const resolveBubbleVisibility = ({ requested, excluded }) =>
  excluded ? 'hide' : requested;
