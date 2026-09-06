// npm i openai   &&   node clients/node_openai.mjs
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: process.env.AI_GATEWAY_URL ?? "http://127.0.0.1:4000/v1",
  apiKey: process.env.AI_GATEWAY_KEY,
});

// Cheap path for bulk work, expensive path only where it earns its keep.
for (const model of ["routine", "balanced"]) {
  const r = await client.chat.completions.create({
    model,
    messages: [{ role: "user", content: "Name one benefit of an LLM gateway, in five words." }],
    max_tokens: 40,
  });
  console.log(`${model} → served by ${r.model}: ${r.choices[0].message.content}`);
}
