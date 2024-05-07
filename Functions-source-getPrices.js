const { ethers } = await import('npm:ethers@6.10.0');

const abiCoder = ethers.AbiCoder.defaultAbiCoder();

const tokenId = args[0];

const apiResponse = await Functions.makeHttpRequest({
    url: `https://api.bridgedataoutput.com/api/v2/OData/test/Property('P_5dba1fb94aa4055b9f29696f')?access_token=6baca547742c6f96a6ff71b138424f21`,
});

const listPrice = Number(apiResponse.data.ListPrice);
const originalListPrice = Number(apiResponse.data.OriginalListPrice);
const taxAssessedValue = Number(apiResponse.data.TaxAssessedValue);

console.log(`List Price: ${listPrice}`);
console.log(`Original List Price: ${originalListPrice}`);
console.log(`Tax Assessed Value: ${taxAssessedValue}`);

const encoded = abiCoder.encode([`uint256`, `uint256`, `uint256`, `uint256`], [tokenId, listPrice, originalListPrice, taxAssessedValue]);

return ethers.getBytes(encoded);
