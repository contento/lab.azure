import figlet from "figlet";

export const allowedFonts = Object.freeze(["Standard", "Small", "Slant"]);
const maximumTextLength = 80;

export function validateGenerationRequest(body) {
  if (!body || typeof body.text !== "string") {
    throw new Error("Text is required.");
  }

  const text = body.text.trim();
  if (!text) {
    throw new Error("Text is required.");
  }

  if (text.length > maximumTextLength) {
    throw new Error(`Text must be ${maximumTextLength} characters or fewer.`);
  }

  const font = typeof body.font === "string" ? body.font : "Standard";
  if (!allowedFonts.includes(font)) {
    throw new Error("The selected font is not supported.");
  }

  return { text, font };
}

export function renderAsciiArt({ text, font }) {
  return figlet.textSync(text, { font });
}
