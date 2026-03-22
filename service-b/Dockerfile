# Service B Dockerfile
FROM node:18

WORKDIR /app

COPY . .

RUN npm install

USER root

CMD ["node", "worker.js"]
