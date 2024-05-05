const { simulateScript } = require("@chainlink/functions-toolkit");
const requestConfig = require('./Functions-request-config');

async function main() {
    const { responseBytesHexstring, capturedTerminalOutput, errorString } = await simulateScript(requestConfig);

    console.log(responseBytesHexstring);
    console.log(errorString)
    console.log(capturedTerminalOutput);
}

// node Functions-simulate-script.js
main();