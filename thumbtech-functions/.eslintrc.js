module.exports = {
  "env": {
    "es6": true,
    "node": true,
  },
  "parserOptions": {
    "ecmaVersion": 2020,
  },
  "extends": [
    "eslint:recommended",
    "google",
  ],
  "rules": {
    "max-len": "off",  // Disable line length checking
    "require-jsdoc": "off",
    "valid-jsdoc": "off",
    "camelcase": "off",
  },
};