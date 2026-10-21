// Startup glue for the PWA shell. Kept in a file (not inline) so the Content-Security-Policy
// can forbid inline scripts.
(function () {
  'use strict';

  // Remove the splash once Flutter has drawn its first frame.
  window.addEventListener('flutter-first-frame', function () {
    var s = document.getElementById('splash');
    if (s) s.remove();
  });

  // Offline support: cache the whole app on first load. Needs a secure context, which
  // includes localhost.
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('aura_sw.js').catch(function () {});
    });
  }
})();
