import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["dist/", "dist-test/"] },
  js.configs.recommended,
  tseslint.configs.recommended,
  {
    rules: {
      // 未定義識別子は TypeScript が検出する。ESLint 側の no-undef は二重チェックになるうえ、
      // 型定義由来のグローバル（process / console / URL 等）を誤検出する。
      "no-undef": "off",
    },
  },
);
