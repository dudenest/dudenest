FROM nginx:alpine
COPY build/web /usr/share/nginx/html
COPY docker/web/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
