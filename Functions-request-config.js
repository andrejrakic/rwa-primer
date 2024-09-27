const fs = require("fs")

// Loads environment variables from .env.enc file (if it exists)
require("@chainlink/env-enc").config()

const Location = {
    Inline: 0,
    Remote: 1,
}

const CodeLanguage = {
    JavaScript: 0,
}

const ReturnType = {
    uint: "uint256",
    uint256: "uint256",
    int: "int256",
    int256: "int256",
    string: "string",
    bytes: "Buffer",
    Buffer: "Buffer",
}

// Configure the request by setting the fields below
const requestConfig = {
    // Location of source code (only Inline is currently supported)
    codeLocation: Location.Inline,
    // Code language (only JavaScript is currently supported)
    codeLanguage: CodeLanguage.JavaScript,
    // String containing the source code to be executed
    source: fs.readFileSync("./Functions-source-getNftMetadata.js").toString(),
    // source: fs.readFileSync("./Functions-source-getPrices.js").toString(),

    // Secrets can be accessed within the source code with `secrets.varName` (ie: secrets.apiKey). The secrets object can only contain string values.
    secrets: {},
    // Per-node secrets objects assigned to each DON member. When using per-node secrets, nodes can only use secrets which they have been assigned.
    perNodeSecrets: [],
    // ETH wallet key used to sign secrets so they cannot be accessed by a 3rd party
    walletPrivateKey: process.env["PRIVATE_KEY"],
    // Args (string only array) can be accessed within the source code with `args[index]` (ie: args[0]).
    args: ["0"],
    // Expected type of the returned value
    expectedReturnType: ReturnType.bytes,
    // Redundant URLs which point to encrypted off-chain secrets
    secretsURLs: [],
}

module.exports = requestConfig