// tools/gemini.mjs
import { GoogleGenerativeAI } from "@google/generative-ai";

async function main() {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.error("GEMINI_API_KEY is not set");
    process.exit(1);
  }
  const prompt = process.argv.slice(2).join(" ").trim() || "Say hello!";
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
  const result = await model.generateContent(prompt);
  const text = result.response.text();
  console.log(text);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
