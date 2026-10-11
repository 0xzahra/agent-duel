// Generates JS-computed commitments (using the SAME web/duel-lib.js the page uses) for test/Vectors.t.sol
globalThis.ethers = require("../web/ethers.umd.min.js");
const L = require("../web/duel-lib.js");
const v = [];
const players = ["0x00000000000000000000000000000000000000A1","0xAAa9DED4E50Ca82E3C32444EA836940612a9FB96","0xFfFFfFfFffFFfFFfFFfFFFFFffFFFfffFfFFFFfF"];
const ids = [1, 2, 7, 123456789, "115792089237316195423570985008687907853269984665640564039457584007913129639935"];
const preds = [0, 1, 2, 127, 255];
for (let i = 0; i < 40; i++) {
  const id = ids[i % ids.length], pred = preds[i % preds.length], player = players[i % players.length], salt = L.randomSalt();
  v.push({ id: ethers.toBeHex(BigInt(id), 32), pred, salt, player: ethers.getAddress(player.toLowerCase()), hash: L.commitmentHash(id, pred, salt, ethers.getAddress(player.toLowerCase())) });
}
require("fs").writeFileSync(__dirname + "/../test/vectors.json", JSON.stringify(v, null, 1));
console.log("wrote", v.length);
