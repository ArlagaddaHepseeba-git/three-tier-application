# ---- Stage 1: build the React app ----
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY public ./public
COPY src ./src
ARG REACT_APP_API_URL=http://localhost:8080/api
ENV REACT_APP_API_URL=$REACT_APP_API_URL
RUN npm run build

# ---- Stage 2: serve the static files with Nginx ----
FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]