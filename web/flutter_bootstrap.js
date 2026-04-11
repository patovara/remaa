{{flutter_js}}
{{flutter_build_config}}

(async function () {
  if ('serviceWorker' in navigator) {
    try {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.map((registration) => registration.unregister()));
    } catch (error) {
      console.warn('No se pudieron desregistrar los service workers existentes.', error);
    }
  }

  _flutter.loader.load({});
})();
