const axios = require('axios');

const SERVICE_A_URL = process.env.SERVICE_A_URL || 'http://localhost:5000';
const INTERVAL_MS = 10000;

async function pollServiceA() {
  try {
    const response = await axios.get(`${SERVICE_A_URL}/data`, { timeout: 5000 });
    console.log(`[${new Date().toISOString()}] Got data from Service A:`, response.data);
  } catch (err) {
    console.error(`[${new Date().toISOString()}] Failed to reach Service A:`, err.message);
  }
}

console.log(`Service B starting. Polling Service A at ${SERVICE_A_URL} every ${INTERVAL_MS / 1000}s`);
setInterval(pollServiceA, INTERVAL_MS);
pollServiceA();
