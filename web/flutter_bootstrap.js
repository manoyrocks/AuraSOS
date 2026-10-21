{{flutter_js}}
{{flutter_build_config}}

// Flutter's own service worker is deprecated (it only unregisters itself), so it is not
// registered here. Offline support comes from aura_sw.js, registered in index.html.
_flutter.loader.load();
