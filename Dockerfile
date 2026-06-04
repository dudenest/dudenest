FROM nginx:alpine
COPY build/web /usr/share/nginx/html
COPY docker/app/nginx.conf /etc/nginx/conf.d/default.conf
# Poison pill: overwrites Flutter's service worker with a self-unregistering version.
# Old browsers that cached the SW will receive this on their next update check,
# which immediately unregisters the SW, clears all caches, and reloads the tab.
RUN printf '%s' \
  'self.addEventListener("install",()=>self.skipWaiting());' \
  'self.addEventListener("activate",e=>{' \
  '  e.waitUntil(' \
  '    self.registration.unregister()' \
  '    .then(()=>caches.keys())' \
  '    .then(ks=>Promise.all(ks.map(k=>caches.delete(k))))' \
  '    .then(()=>self.clients.matchAll({type:"window"}))' \
  '    .then(cs=>cs.forEach(c=>c.navigate(c.url)))' \
  '  );' \
  '});' \
  > /usr/share/nginx/html/flutter_service_worker.js
EXPOSE 80
