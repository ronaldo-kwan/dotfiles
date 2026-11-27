// ESLint for the website's scripts (site/), run by scripts/lint.sh. The pages load them as
// plain scripts, in order: theme.js, common.js, then app.js or docs/docs.js. So what
// common.js defines at the top level is shared with the others, which use it as globals.
import js from "@eslint/js";
import globals from "globals";

// What common.js defines for the page scripts that load after it.
const shared = { $: "readonly", THEME: "readonly", CALM: "readonly", toast: "readonly", setupTheme: "readonly", setupNav: "readonly" };

export default [
  js.configs.recommended,
  {
    files: ["site/**/*.js"],
    languageOptions: { ecmaVersion: 2022, sourceType: "script", globals: { ...globals.browser } },
    linterOptions: { reportUnusedDisableDirectives: "error" },
    rules: {
      eqeqeq: ["error", "always", { null: "ignore" }],
      "no-implicit-globals": "off",
      "prefer-const": "error",
      "no-var": "error",
    },
  },
  // common.js is shared: its top-level names are used by the other scripts, not by itself.
  { files: ["site/common.js"], rules: { "no-unused-vars": ["error", { vars: "local" }] } },
  { files: ["site/app.js", "site/docs/docs.js"], languageOptions: { globals: shared } },
];
