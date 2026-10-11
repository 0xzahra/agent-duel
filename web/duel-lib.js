// Pure helpers shared by the page and the tests. Needs ethers v6 as global `ethers`.
(function (root) {
  const E = () => root.ethers;
  // Exactly the contract: keccak256(abi.encode(uint256 id, uint8 prediction, bytes32 salt, address player))
  function commitmentHash(id, prediction, salt, player) {
    const e = E();
    return e.keccak256(e.AbiCoder.defaultAbiCoder().encode(
      ["uint256", "uint8", "bytes32", "address"], [BigInt(id), Number(prediction), salt, player]));
  }
  function randomSalt() {
    const b = new Uint8Array(32);
    (root.crypto || require("crypto").webcrypto).getRandomValues(b);
    return E().hexlify(b);
  }
  function buildNote(o) {
    return ["AGENT DUEL REVEAL NOTE - KEEP SECRET UNTIL REVEAL TIME",
      "contract: " + o.contract, "chainId: " + o.chainId, "question: " + o.id, "wallet: " + o.player,
      "prediction: " + o.prediction, "salt: " + o.salt, "commitment: " + o.commitment, ""].join("\n");
  }
  function parseNote(t) {
    const g = k => { const m = new RegExp("^" + k + ":\\s*(\\S+)", "mi").exec(t); return m ? m[1] : null; };
    const r = { id: g("question"), player: g("wallet"), prediction: g("prediction"), salt: g("salt"), contract: g("contract") };
    return r.id && r.prediction !== null && /^0x[0-9a-fA-F]{64}$/.test(r.salt || "") ? r : null;
  }
  const api = { commitmentHash, randomSalt, buildNote, parseNote };
  root.DuelLib = api;
  if (typeof module !== "undefined") module.exports = api;
})(typeof window !== "undefined" ? window : globalThis);
