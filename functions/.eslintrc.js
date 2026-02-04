module.exports = {
  env: {
    node: true,
    es2022: true,
  },
  extends: ["eslint:recommended"],
  parserOptions: {
    ecmaVersion: 2022,
  },
  rules: {
    // نخلي اللينت خفيف حتى ما يوقف الـ deploy بسبب تنسيق
    "no-unused-vars": ["warn", { argsIgnorePattern: "^_" }],
    "max-len": "off",
    "object-curly-spacing": "off",
  },
};
