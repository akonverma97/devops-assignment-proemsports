FROM node:18-slim

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .

RUN adduser --disabled-password --gecos "" appuser
USER appuser

CMD ["node", "worker.js"]