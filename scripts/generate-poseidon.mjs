#!/usr/bin/env node
// Generates protocol/contracts/src/libraries/Bn254Poseidon.sol from the Poseidon
// parameters recorded in protocol/setup/v2/manifest.json.
//
// The emitted library keeps the ABI of the generic implementation (hash3, hash5,
// hash3PairPath32) and produces identical outputs, but runs the permutation fully
// unrolled with every constant as an immediate. Partial rounds use the equivalent
// sparse-matrix form from the Poseidon paper (Grassi et al., appendix B): the
// round constants on the two non-S-boxed lanes are folded forward, and each
// partial-round MDS multiplication is split into a dense part that moves into the
// previous round and a sparse part (5 field multiplications instead of 9).
//
//   node scripts/generate-poseidon.mjs          # rewrite the library
//   node scripts/generate-poseidon.mjs --check  # exit 1 if the checked-in file differs

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const manifestPath = path.join(root, 'protocol/setup/v2/manifest.json');
const outputPath = path.join(root, 'protocol/contracts/src/libraries/Bn254Poseidon.sol');
const check = process.argv.includes('--check');

const params = JSON.parse(fs.readFileSync(manifestPath, 'utf8')).poseidon;
const F = BigInt(params.field_modulus);
const T = params.rate + params.capacity;
const RF = params.full_rounds;
const RP = params.partial_rounds;
const HALF = RF / 2;
const ROUNDS = RF + RP;
const RC = params.round_constants.map(BigInt);
const MDS = params.mds.map(BigInt);

if (T !== 3 || params.capacity !== 1 || params.alpha !== 5 || RF % 2 !== 0) {
  throw new Error('generator supports width 3, capacity 1, x^5 S-box, even full round count');
}
if (RC.length !== T * ROUNDS || MDS.length !== T * T) throw new Error('unexpected constant count');
if (5n * F >= 2n ** 256n) throw new Error('unreduced sums of five field elements must fit in 256 bits');
for (const value of [...RC, ...MDS]) if (value >= F) throw new Error('constant out of field');

const mod = value => ((value % F) + F) % F;
const pow = (base, exponent) => {
  let result = 1n;
  base = mod(base);
  for (let e = exponent; e > 0n; e >>= 1n) {
    if (e & 1n) result = (result * base) % F;
    base = (base * base) % F;
  }
  return result;
};
const inverse = value => pow(value, F - 2n);
const M = [MDS.slice(0, 3), MDS.slice(3, 6), MDS.slice(6, 9)];
const C = Array.from({ length: ROUNDS }, (_, r) => RC.slice(3 * r, 3 * r + 3));
const isFull = r => r < HALF || r >= HALF + RP;
const matVec = (A, s) => A.map(row => mod(row[0] * s[0] + row[1] * s[1] + row[2] * s[2]));
const matMul = (A, B) =>
  A.map(row => B[0].map((_, j) => mod(row.reduce((acc, value, k) => acc + value * B[k][j], 0n))));
const hex = value => `0x${value.toString(16).padStart(64, '0')}`;

// Reference permutation, exactly as the generic library computes it.
function permuteReference(input) {
  let s = input.map(mod);
  for (let r = 0; r < ROUNDS; r++) {
    s = s.map((value, i) => mod(value + C[r][i]));
    s[0] = pow(s[0], 5n);
    if (isFull(r)) {
      s[1] = pow(s[1], 5n);
      s[2] = pow(s[2], 5n);
    }
    s = matVec(M, s);
  }
  return s;
}

// Step 1: a partial round only S-boxes lane 0, so the constants added to lanes 1
// and 2 pass through the S-box layer untouched and M·(0, c1, c2) can be added to
// the next round's constants instead.
const folded = C.map(row => [...row]);
for (let r = HALF; r < HALF + RP; r++) {
  const carried = matVec(M, [0n, folded[r][1], folded[r][2]]);
  folded[r][1] = 0n;
  folded[r][2] = 0n;
  folded[r + 1] = folded[r + 1].map((value, i) => mod(value + carried[i]));
}

// Step 2: walking the partial rounds backwards, factor the current matrix as
// M'' · M' with M' = diag(1, Mhat). M' only mixes lanes 1 and 2, so it commutes
// with the partial S-box and moves into the previous round, whose matrix becomes
// M' · M. The sparse M'' keeps row 0 (m00, vhat) and column 0 (m00, w) and is the
// identity elsewhere. The chain ends in the last full round of the first half.
const sparse = new Array(ROUNDS).fill(null);
let current = M.map(row => [...row]);
for (let r = HALF + RP - 1; r >= HALF; r--) {
  const [a, b, c, d] = [current[1][1], current[1][2], current[2][1], current[2][2]];
  const det = inverse(mod(a * d - b * c));
  const hatInverse = [
    [mod(d * det), mod(-b * det)],
    [mod(-c * det), mod(a * det)],
  ];
  const v = [current[0][1], current[0][2]];
  const vhat = [
    mod(v[0] * hatInverse[0][0] + v[1] * hatInverse[1][0]),
    mod(v[0] * hatInverse[0][1] + v[1] * hatInverse[1][1]),
  ];
  sparse[r] = { m00: current[0][0], vhat, w: [current[1][0], current[2][0]] };
  const moved = [
    [1n, 0n, 0n],
    [0n, a, b],
    [0n, c, d],
  ];
  current = matMul(moved, M);
}
const lastFirstHalfMatrix = current;
const m00 = sparse[HALF].m00;
if (sparse.some(entry => entry && entry.m00 !== m00)) throw new Error('m00 is expected to be round independent');

function permuteOptimized(input) {
  let s = input.map(mod);
  for (let r = 0; r < ROUNDS; r++) {
    if (isFull(r)) {
      s = s.map((value, i) => pow(value + folded[r][i], 5n));
      s = matVec(r === HALF - 1 ? lastFirstHalfMatrix : M, s);
    } else {
      const { vhat, w } = sparse[r];
      const x = pow(s[0] + folded[r][0], 5n);
      s = [mod(m00 * x + vhat[0] * s[1] + vhat[1] * s[2]), mod(w[0] * x + s[1]), mod(w[1] * x + s[2])];
    }
  }
  return s;
}

const hash = (permute, inputs) => {
  let s = [0n, inputs[0], inputs[1]];
  for (let i = 2; i < inputs.length; i += 2) {
    s = permute(s);
    s[1] = mod(s[1] + inputs[i]);
    if (i + 1 < inputs.length) s[2] = mod(s[2] + inputs[i + 1]);
  }
  return permute(s)[1];
};

// Refuse to emit anything unless the rewritten schedule matches the reference.
let seed = 0x5eedn;
const next = () => (seed = (seed * 6364136223846793005n + 1442695040888963407n) % 2n ** 256n);
const samples = [[0n, 0n, 0n], [F - 1n, F - 1n, F - 1n], [1n, 2n, 3n]];
for (let i = 0; i < 64; i++) samples.push([next(), next(), next()]);
for (const sample of samples) {
  const expected = permuteReference(sample);
  const actual = permuteOptimized(sample);
  if (expected.some((value, i) => value !== actual[i])) throw new Error('optimized permutation diverged');
}
for (const permute of [permuteReference, permuteOptimized]) {
  if (hash(permute, [1n, 2n, 3n]) !== BigInt(params.test_hash3)) throw new Error('hash3 vector mismatch');
  if (hash(permute, [1n, 2n, 3n, 4n, 5n]) !== BigInt(params.test_hash5)) throw new Error('hash5 vector mismatch');
}

// Code generation notes, all measured on solc 0.8.28 with the IR pipeline the project uses:
//  * The modulus, zero and m00 are derived from `calldatasize` at runtime (`_constants`, and the top of
//    `_permute`) rather than written as literals. A literal would be re-pushed at each of its ~700 uses
//    per permutation, and the constant optimiser then routes any literal that repeats often enough
//    through CODECOPY (at optimizer_runs = 200 already from three uses). Runtime values stay as plain
//    stack slots.
//  * Matrix entries of the seven identical full rounds are written as `m + k * p` for k in 0..4, which
//    `mulmod` reduces away, so no literal appears more than twice.
//  * The IR stack layout generator handles about fifty field operations per basic block before it
//    starts spilling to memory, so a branch on `zero` that never executes separates every few rounds.
const GUARD_UNITS = 3;
const emitted = [];
const emit = (indent, text) => emitted.push(`${'    '.repeat(indent)}${text}`);
const offset = (value, k) => hex(value + BigInt(k) * F);
// One lane of the matrix multiplication as three statements, which keeps every line within forge fmt's width.
const mix = (indent, lane, A, i, x, k, first) => {
  emit(indent, `${lane} := ${first || `mulmod(${x[0]}, ${offset(A[i][0], k)}, f)`}`);
  emit(indent, `${lane} := add(${lane}, mulmod(${x[1]}, ${offset(A[i][1], k)}, f))`);
  emit(indent, `${lane} := add(${lane}, mulmod(${x[2]}, ${offset(A[i][2], k)}, f))`);
};
const guard = () => emit(3, `if zero { f := 0 }`);

let units = 0;
let plainFullRounds = 0;
for (let r = 0; r < ROUNDS; r++) {
  const full = isFull(r);
  if (units >= GUARD_UNITS) {
    guard();
    units = 0;
  }
  units += full ? 2 : 1;
  emit(3, `{`);
  if (full) {
    const special = r === HALF - 1;
    const A = special ? lastFirstHalfMatrix : M;
    const k = special ? 0 : plainFullRounds++ % 5;
    emit(4, `// full round ${r}${special ? ' (matrix includes the dense factors moved out of the partial rounds)' : ''}`);
    emit(4, `let x0 := add(s0, ${hex(folded[r][0])})`);
    emit(4, `let x1 := add(s1, ${hex(folded[r][1])})`);
    emit(4, `let x2 := add(s2, ${hex(folded[r][2])})`);
    emit(4, `let q := mulmod(x0, x0, f)`);
    emit(4, `x0 := mulmod(mulmod(q, q, f), x0, f)`);
    emit(4, `q := mulmod(x1, x1, f)`);
    emit(4, `x1 := mulmod(mulmod(q, q, f), x1, f)`);
    emit(4, `q := mulmod(x2, x2, f)`);
    emit(4, `x2 := mulmod(mulmod(q, q, f), x2, f)`);
    mix(4, 's0', A, 0, ['x0', 'x1', 'x2'], k, special ? null : 'mulmod(x0, m00, f)');
    mix(4, 's1', A, 1, ['x0', 'x1', 'x2'], k);
    mix(4, 's2', A, 2, ['x0', 'x1', 'x2'], k);
  } else {
    const { vhat, w } = sparse[r];
    emit(4, `// partial round ${r}`);
    emit(4, `let x := add(s0, ${hex(folded[r][0])})`);
    emit(4, `let q := mulmod(x, x, f)`);
    emit(4, `x := mulmod(mulmod(q, q, f), x, f)`);
    emit(4, `let n0 := mulmod(x, m00, f)`);
    emit(4, `n0 := add(n0, mulmod(s1, ${hex(vhat[0])}, f))`);
    emit(4, `s0 := add(n0, mulmod(s2, ${hex(vhat[1])}, f))`);
    emit(4, `s1 := addmod(mulmod(x, ${hex(w[0])}, f), s1, f)`);
    emit(4, `s2 := addmod(mulmod(x, ${hex(w[1])}, f), s2, f)`);
  }
  emit(3, `}`);
}
const rounds = emitted.join('\n');

const source = `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// GENERATED FILE. Do not edit by hand.
// Source: protocol/setup/v2/manifest.json (poseidon), generator: scripts/generate-poseidon.mjs.
// Verify: node scripts/generate-poseidon.mjs --check

/// @title Bn254Poseidon
/// @notice Poseidon over the BN254 scalar field, generated from zkAPI v2's arkworks parameters.
/// @dev Width 3, rate 2, x^5 S-box, ${RF} full rounds, and ${RP} partial rounds. Same interface and
/// outputs as the straightforward evaluation of these parameters (kept in
/// test/reference/Bn254PoseidonReference.sol), but the permutation is fully unrolled with the round
/// constants and matrix entries as immediates, and the partial rounds run in the equivalent sparse form
/// from the Poseidon paper: their round constants on the two lanes without an S-box are folded forward,
/// and each partial-round matrix is split into a dense factor that moves into the previous round and a
/// sparse remainder (five multiplications instead of nine).
///
/// Lane values are only partially reduced between rounds: the operands of every \`add\` sum to less than
/// five times the modulus, which fits in 256 bits, and \`mulmod\`/\`addmod\` reduce their inputs. Callers
/// of \`_permute\` pass reduced inputs or the outputs of a previous permutation; its outputs are below
/// three times the modulus.
///
/// Matrix entries of the identical full rounds are written as the entry plus a small multiple of the
/// modulus (\`mulmod\` reduces it), so that no 32-byte literal repeats enough for the constant optimiser
/// to route it through CODECOPY. The modulus, zero and the shared entry m00 are derived from
/// \`calldatasize\` for the same reason, and the never-taken \`if zero\` branches between rounds keep the IR
/// stack layout generator from spilling to memory on one very long basic block.
library Bn254Poseidon {
    uint256 internal constant FIELD_MODULUS =
        ${F.toString()};

    function hash3(uint256 a, uint256 b, uint256 c) public pure returns (uint256 result) {
        (uint256 f,) = _constants();
        result = _hash3(a % f, b % f, c);
    }

    function hash5(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e) public pure returns (uint256 result) {
        (uint256 f, uint256 zero) = _constants();
        (uint256 s0, uint256 s1, uint256 s2) = _permute(zero, a % f, b % f);
        (s0, s1, s2) = _permute(s0, addmod(s1, c, f), addmod(s2, d, f));
        (, s1,) = _permute(s0, addmod(s1, e, f), s2);
        result = s1 % f;
    }

    function hash3PairPath32(
        uint256 domain,
        uint32 index,
        uint256 oldLeaf,
        uint256 newLeaf,
        uint256[32] calldata siblings
    ) public pure returns (uint256 oldRoot, uint256 newRoot) {
        (uint256 f,) = _constants();
        domain %= f;
        oldRoot = oldLeaf % f;
        newRoot = newLeaf % f;
        for (uint256 level = 0; level < 32;) {
            uint256 sibling = siblings[level] % f;
            if (((index >> level) & 1) == 0) {
                oldRoot = _hash3(domain, oldRoot, sibling);
                newRoot = _hash3(domain, newRoot, sibling);
            } else {
                oldRoot = _hash3(domain, sibling, oldRoot);
                newRoot = _hash3(domain, sibling, newRoot);
            }
            unchecked {
                ++level;
            }
        }
    }

    /// @dev The modulus and zero as runtime values rather than literals (see the note above).
    /// \`shr(255, calldatasize())\` is zero for any calldata that fits in a block.
    function _constants() private pure returns (uint256 f, uint256 zero) {
        assembly ("memory-safe") {
            zero := shr(255, calldatasize())
            f := add(FIELD_MODULUS, zero)
        }
    }

    /// @dev Inputs \`a\` and \`b\` must be reduced below the modulus; the output is reduced.
    function _hash3(uint256 a, uint256 b, uint256 c) private pure returns (uint256 result) {
        (uint256 f, uint256 zero) = _constants();
        (uint256 s0, uint256 s1, uint256 s2) = _permute(zero, a, b);
        (, s1,) = _permute(s0, addmod(s1, c, f), s2);
        result = s1 % f;
    }

    /// @dev One Poseidon permutation. Lanes must be below four times the modulus on entry and are below
    /// three times the modulus on exit.
    function _permute(uint256 s0, uint256 s1, uint256 s2) private pure returns (uint256, uint256, uint256) {
        assembly ("memory-safe") {
            let zero := shr(255, calldatasize())
            let f := add(FIELD_MODULUS, zero)
            let m00 := add(${hex(m00)}, zero)
${rounds}
        }
        return (s0, s1, s2);
    }
}
`;

if (check) {
  const existing = fs.existsSync(outputPath) ? fs.readFileSync(outputPath, 'utf8') : null;
  if (existing !== source) {
    console.error(`${path.relative(root, outputPath)} is out of date; run node scripts/generate-poseidon.mjs`);
    process.exit(1);
  }
  console.log(`${path.relative(root, outputPath)} matches the generator output`);
} else {
  fs.writeFileSync(outputPath, source);
  console.log(`Wrote ${path.relative(root, outputPath)} (${source.length} bytes)`);
}
