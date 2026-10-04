// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// GENERATED FILE. Do not edit by hand.
// Source: protocol/setup/v2/manifest.json (poseidon), generator: scripts/generate-poseidon.mjs.
// Verify: node scripts/generate-poseidon.mjs --check

/// @title Bn254Poseidon
/// @notice Poseidon over the BN254 scalar field, generated from zkAPI v2's arkworks parameters.
/// @dev Width 3, rate 2, x^5 S-box, 8 full rounds, and 57 partial rounds. Same interface and
/// outputs as the straightforward evaluation of these parameters (kept in
/// test/reference/Bn254PoseidonReference.sol), but the permutation is fully unrolled with the round
/// constants and matrix entries as immediates, and the partial rounds run in the equivalent sparse form
/// from the Poseidon paper: their round constants on the two lanes without an S-box are folded forward,
/// and each partial-round matrix is split into a dense factor that moves into the previous round and a
/// sparse remainder (five multiplications instead of nine).
///
/// Lane values are only partially reduced between rounds: the operands of every `add` sum to less than
/// five times the modulus, which fits in 256 bits, and `mulmod`/`addmod` reduce their inputs. Callers
/// of `_permute` pass reduced inputs or the outputs of a previous permutation; its outputs are below
/// three times the modulus.
///
/// Matrix entries of the identical full rounds are written as the entry plus a small multiple of the
/// modulus (`mulmod` reduces it), so that no 32-byte literal repeats enough for the constant optimiser
/// to route it through CODECOPY. The modulus, zero and the shared entry m00 are derived from
/// `calldatasize` for the same reason, and the never-taken `if zero` branches between rounds keep the IR
/// stack layout generator from spilling to memory on one very long basic block.
library Bn254Poseidon {
    uint256 internal constant FIELD_MODULUS =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

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
    /// `shr(255, calldatasize())` is zero for any calldata that fits in a block.
    function _constants() private pure returns (uint256 f, uint256 zero) {
        assembly ("memory-safe") {
            zero := shr(255, calldatasize())
            f := add(FIELD_MODULUS, zero)
        }
    }

    /// @dev Inputs `a` and `b` must be reduced below the modulus; the output is reduced.
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
            let m00 := add(0x109b7f411ba0e4c9b2b70caf5c36a7b194be7c11ad24378bfedb68592ba8118b, zero)
            {
                // full round 0
                let x0 := add(s0, 0x0ee9a592ba9a9518d05986d656f40c2114c4993c11bb29938d21d47304cd8e6e)
                let x1 := add(s1, 0x00f1445235f2148c5986587169fc1bcd887b08d4d00868df5696fff40956e864)
                let x2 := add(s2, 0x08dff3487e8ac99e1f29a058d0fa80b930c728730b7ab36ce879f3890ecf73f5)
                let q := mulmod(x0, x0, f)
                x0 := mulmod(mulmod(q, q, f), x0, f)
                q := mulmod(x1, x1, f)
                x1 := mulmod(mulmod(q, q, f), x1, f)
                q := mulmod(x2, x2, f)
                x2 := mulmod(mulmod(q, q, f), x2, f)
                s0 := mulmod(x0, m00, f)
                s0 := add(s0, mulmod(x1, 0x16ed41e13bb9c0c66ae119424fddbcbc9314dc9fdbdeea55d6c64543dc4903e0, f))
                s0 := add(s0, mulmod(x2, 0x2b90bba00fca0589f617e7dcbfe82e0df706ab640ceb247b791a93b74e36736d, f))
                s1 := mulmod(x0, 0x2969f27eed31a480b9c36c764379dbca2cc8fdd1415c3dded62940bcde0bd771, f)
                s1 := add(s1, mulmod(x1, 0x2e2419f9ec02ec394c9871c832963dc1b89d743c8c7b964029b2311687b1fe23, f))
                s1 := add(s1, mulmod(x2, 0x101071f0032379b697315876690f053d148d4e109f5fb065c8aacc55a0f89bfa, f))
                s2 := mulmod(x0, 0x143021ec686a3f330d5f9e654638065ce6cd79e28c5b3753326244ee65a1b1a7, f)
                s2 := add(s2, mulmod(x1, 0x176cc029695ad02582a70eff08a6fd99d057e12e58e7d7b6b16cdfabc8ee2911, f))
                s2 := add(s2, mulmod(x2, 0x19a3fc0a56702bf417ba7fee3802593fa644470307043f7773279cd71d25d5e0, f))
            }
            {
                // full round 1
                let x0 := add(s0, 0x2f27be690fdaee46c3ce28f7532b13c856c35342c84bda6e20966310fadc01d0)
                let x1 := add(s1, 0x2b2ae1acf68b7b8d2416bebf3d4f6234b763fe04b8043ee48b8327bebca16cf2)
                let x2 := add(s2, 0x0319d062072bef7ecca5eac06f97d4d55952c175ab6b03eae64b44c7dbf11cfa)
                let q := mulmod(x0, x0, f)
                x0 := mulmod(mulmod(q, q, f), x0, f)
                q := mulmod(x1, x1, f)
                x1 := mulmod(mulmod(q, q, f), x1, f)
                q := mulmod(x2, x2, f)
                x2 := mulmod(mulmod(q, q, f), x2, f)
                s0 := mulmod(x0, m00, f)
                s0 := add(s0, mulmod(x1, 0x475190541ceb60f023315ef8d15f1519bb48c4e855985ae71aa83ad7cc4903e1, f))
                s0 := add(s0, mulmod(x2, 0x5bf50a12f0fba5b3ae682d934169866b1f3a93ac86a4950cbcfc894b3e36736e, f))
                s1 := mulmod(x0, 0x59ce40f1ce6344aa7213b22cc4fb342754fce619bb15ae701a0b3650ce0bd772, f)
                s1 := add(s1, mulmod(x1, 0x5e88686ccd348c6304e8b77eb417961ee0d15c85063506d16d9426aa77b1fe24, f))
                s1 := add(s1, mulmod(x2, 0x4074c062e45519e04f819e2cea905d9a3cc13659191920f70c8cc1e990f89bfb, f))
                s2 := mulmod(x0, 0x4494705f499bdf5cc5afe41bc7b95eba0f01622b0614a7e476443a8255a1b1a8, f)
                s2 := add(s2, mulmod(x1, 0x47d10e9c4a8c704f3af754b58a2855f6f88bc976d2a14847f54ed53fb8ee2912, f))
                s2 := add(s2, mulmod(x2, 0x4a084a7d37a1cc1dd00ac5a4b983b19cce782f4b80bdb008b709926b0d25d5e1, f))
            }
            if zero { f := 0 }
            {
                // full round 2
                let x0 := add(s0, 0x28813dcaebaeaa828a376df87af4a63bc8b7bf27ad49c6298ef7b387bf28526d)
                let x1 := add(s1, 0x2727673b2ccbc903f181bf38e1c1d40d2033865200c352bc150928adddf9cb78)
                let x2 := add(s2, 0x234ec45ca27727c2e74abd2b2a1494cd6efbd43e340587d6b8fb9e31e65cc632)
                let q := mulmod(x0, x0, f)
                x0 := mulmod(mulmod(q, q, f), x0, f)
                q := mulmod(x1, x1, f)
                x1 := mulmod(mulmod(q, q, f), x1, f)
                q := mulmod(x2, x2, f)
                x2 := mulmod(mulmod(q, q, f), x2, f)
                s0 := mulmod(x0, m00, f)
                s0 := add(s0, mulmod(x1, 0x77b5dec6fe1d0119db81a4af52e06d76e37cad30cf51cb785e8a306bbc4903e2, f))
                s0 := add(s0, mulmod(x2, 0x8c595885d22d45dd66b87349c2eadec8476e7bf5005e059e00de7edf2e36736f, f))
                s1 := mulmod(x0, 0x8a328f64af94e4d42a63f7e3467c8c847d30ce6234cf1f015ded2be4be0bd773, f)
                s1 := add(s1, mulmod(x1, 0x8eecb6dfae662c8cbd38fd353598ee7c090544cd7fee7762b1761c3e67b1fe25, f))
                s1 := add(s1, mulmod(x2, 0x70d90ed5c586ba0a07d1e3e36c11b5f764f51ea192d29188506eb77d80f89bfc, f))
                s2 := mulmod(x0, 0x74f8bed22acd7f867e0029d2493ab71737354a737fce1875ba26301645a1b1a9, f)
                s2 := add(s2, mulmod(x1, 0x78355d0f2bbe1078f3479a6c0ba9ae5420bfb1bf4c5ab8d93930cad3a8ee2913, f))
                s2 := add(s2, mulmod(x2, 0x7a6c98f018d36c47885b0b5b3b0509f9f6ac1793fa772099faeb87fefd25d5e2, f))
            }
            {
                // full round 3 (matrix includes the dense factors moved out of the partial rounds)
                let x0 := add(s0, 0x15b52534031ae18f7f862cb2cf7cf760ab10a8150a337b1ccd99ff6e8797d428)
                let x1 := add(s1, 0x0dc8fad6d9e4b35f5ed9a3d186b79ce38e0e8a8d1b58b132d701d4eecf68d1f6)
                let x2 := add(s2, 0x1bcd95ffc211fbca600f705fad3fb567ea4eb378f62e1fec97805518a47e4d9c)
                let q := mulmod(x0, x0, f)
                x0 := mulmod(mulmod(q, q, f), x0, f)
                q := mulmod(x1, x1, f)
                x1 := mulmod(mulmod(q, q, f), x1, f)
                q := mulmod(x2, x2, f)
                x2 := mulmod(mulmod(q, q, f), x2, f)
                s0 := mulmod(x0, 0x109b7f411ba0e4c9b2b70caf5c36a7b194be7c11ad24378bfedb68592ba8118b, f)
                s0 := add(s0, mulmod(x1, 0x16ed41e13bb9c0c66ae119424fddbcbc9314dc9fdbdeea55d6c64543dc4903e0, f))
                s0 := add(s0, mulmod(x2, 0x2b90bba00fca0589f617e7dcbfe82e0df706ab640ceb247b791a93b74e36736d, f))
                s1 := mulmod(x0, 0x1e6f20a11d1e31e43f83dcedddb9a0236203f5f24ae72c925a8a79a66831f51d, f)
                s1 := add(s1, mulmod(x1, 0x2d51ba82c8073c6d6bacf1ad5e56655b7143625b0a9e9c3190527a1a5f05079a, f))
                s1 := add(s1, mulmod(x2, 0x11e12a40d262ae88e8376f62d19edf43093cdef1ccf34d985a3e53f0bc5765a0, f))
                s2 := mulmod(x0, 0x1bd8c528472e57bdc722a141f8785694484f426725403ae24084e3027e782467, f)
                s2 := add(s2, mulmod(x1, 0x1b07d6d51e6f7e97e0ab10fc2e51ea83ce0611f940ff0731b5f927fe8d6a77c9, f))
                s2 := add(s2, mulmod(x2, 0x221c170e4d02a2479c6f3e47b5ff55781574f980d89038308a3ef37cce8463bd, f))
            }
            if zero { f := 0 }
            {
                // partial round 4
                let x := add(s0, 0x10520b0ab721cadfe9eff81b016fc34dc76da36c2578937817cb978d069de559)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x03f0815ab463f1b76ee25a9b8768b3231a89752f427f4f063ab718e707576b31, f))
                s0 := add(n0, mulmod(s2, 0x15648bf46f60d82954c7e33029b3617357012a3d3b1d34c8e008859f1dbfb317, f))
                s1 := addmod(mulmod(x, 0x127e00c2253de07818ca7f2eafdd7564d05ea850cf61f1daa0cfefbf7fbfba85, f), s1, f)
                s2 := addmod(mulmod(x, 0x066365afd18a41ef9382fc0b1d265cb4d3ce470a8cbbb878f7d48051630747bd, f), s2, f)
            }
            {
                // partial round 5
                let x := add(s0, 0x0a8526e9d9e0da22ce8d94e263a8ed5484d34614da2d768462cdf6dea7989b6b)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x219d14f823513140dc69a96f7fe7e086f4fa24c84e57dcf2b099715c4404aae7, f))
                s0 := add(n0, mulmod(s2, 0x03a30bfbbf2cb86d4a6a63a8050d91f9f14f4d33696d37ebaefa9ac2302132d5, f))
                s1 := addmod(mulmod(x, 0x2121bbcdeaa33a35b0270fb7d5c9f94edad5a84d74b06e3385104b0b41935bcc, f), s1, f)
                s2 := addmod(mulmod(x, 0x196b544fbeb0a792cfbb82c289e579b7cd5580c2e338a389d053ef8b3d10e70e, f), s2, f)
            }
            {
                // partial round 6
                let x := add(s0, 0x1116fa006c17831ef3dc42d9dbeb7721d6372943d145e1d3572ce1e83d658fa7)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2809c3a1547c0cee89c1db270ef479c26973ec73edb4bd4e7d907ea0202f560f, f))
                s0 := add(n0, mulmod(s2, 0x11c34446b083ef92ca157585a02b8b342a4c67175b31f4b5d40d4e96dfc5c8f1, f))
                s1 := addmod(mulmod(x, 0x253ea0b33a8bf3b2367c030e3289cbe0f6242ad7709d90b86d9d8026e2e39925, f), s1, f)
                s2 := addmod(mulmod(x, 0x30467dc1930f6afe90c89d4007ad29fc4f5a19c006d1030438c16df85637bd5f, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 7
                let x := add(s0, 0x238ce638b7f429c554db135a56b841dd1fafe5dbe5273eb1209a3d6fe16b702d)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2f9d4b55495f7e377e20e6f5a3a88af7aa6a536458b38bbe13c8ebfbbba54f44, f))
                s0 := add(n0, mulmod(s2, 0x1d9e9d5c736e3151f11d36d499e7e093d8ee2353be18aad54cfd03ff0feac4b8, f))
                s1 := addmod(mulmod(x, 0x124b617b43e598f9ebf622f7823a3de7d1bfedb87e097c315f343de301e54841, f), s1, f)
                s2 := addmod(mulmod(x, 0x198e7cfc66ae45774055cf073bedc945a5f9c5b19cae08d789cc5748ffe199b2, f), s2, f)
            }
            {
                // partial round 8
                let x := add(s0, 0x00185e9e6073fb916566e21fa72193d0f59a108b25eab222004ea72a8ffa97c1)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2eac25b3498dfadffd124ab3aad57789eb945ba57443099c5bb6c27ed977fe24, f))
                s0 := add(n0, mulmod(s2, 0x1ee02c175cdfe1871b378305c1bb9c904e8af1d4454ed3550b3c6ab5f4f90126, f))
                s1 := addmod(mulmod(x, 0x0616f8c34c607266b29ea8f9d2dfa47ff6fbb1d9745c48609fa98301d0f679d5, f), s1, f)
                s2 := addmod(mulmod(x, 0x181d68b0a188504958b9f19cbbdb972a853e51ed385e4883a43a42832803370b, f), s2, f)
            }
            {
                // partial round 9
                let x := add(s0, 0x116b402e300eb1750f4df186e918430eb2d7c0b94a317e1793a6a75278312c37)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2d5397ce863464a25d6b7f5b015d579181d1ce2f24cbabf6059e9327f5ba7004, f))
                s0 := add(n0, mulmod(s2, 0x15bf817491b94d71e8912940cc0b80277713e7d32da2b6591724d8dbd4bc2618, f))
                s1 := addmod(mulmod(x, 0x2a7cbd11460b177ab76feab28b69485ac8cc687740bc910994a3827d29c08714, f), s1, f)
                s2 := addmod(mulmod(x, 0x0f7cd5ffa4661730ab56e447fae5cc1763cb462da80a85614c237b290de9d502, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 10
                let x := add(s0, 0x06f7d4fce8d01aa6f063f5833010675fb4411547923229bd250e9f18734785b0)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x0e0766004b4c4176eb13273508eb6575f768137d86d305be644ce04531008100, f))
                s0 := add(n0, mulmod(s2, 0x0625fa7145813481f6d148be6b9c8bb7b54ee3c1afac00104e1f763000b9924c, f))
                s1 := addmod(mulmod(x, 0x007c5472508b459916ee0f5461aad2e0b19cd9c7b184f515b65136318ce2c6a5, f), s1, f)
                s2 := addmod(mulmod(x, 0x0567375470d189b693ac77ab3fb7557231d53073951d43c54685879cb7a89fcb, f), s2, f)
            }
            {
                // partial round 11
                let x := add(s0, 0x0d7009d0dd50d1342d220cb69068ff9a575a903940d403f3973f00ad3a988e61)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x1d0406bcbec83f8d5165f56c063e42108ad21f51ea4bfc71601174ba5c7b8bcc, f))
                s0 := add(n0, mulmod(s2, 0x0c02b18eef22332d280a8aa1f86405f3375f06342f8696ee7c73b46c63272cb7, f))
                s1 := addmod(mulmod(x, 0x17c1fc174cd9a6ebeaa7add2f801a664823509ad4fd1b15aad053a55ad6da4cf, f), s1, f)
                s2 := addmod(mulmod(x, 0x05f843c23024eb1dab7ebbc86709a021aaa6caf433f7ed258a08638e9584b32d, f), s2, f)
            }
            {
                // partial round 12
                let x := add(s0, 0x07bf939ea61266e66e09daa5c95a2d475ea85006fd8202ac451fbdaf4d7713fd)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x22df2420697ca28b5cc51c53165e002727b45ccd90a55c87589f792f0ad8cb37, f))
                s0 := add(n0, mulmod(s2, 0x2f1438303a7b49d473400aaedf0f48009fd3af804b76be86417588efc4d7302a, f))
                s1 := addmod(mulmod(x, 0x2323d5fcf2da8965c6b2b7b4fbf9a24bbaa7f4dccd35d5ca6155c5463093b23b, f), s1, f)
                s2 := addmod(mulmod(x, 0x026c85b9dfbbe48fe83b753a5e7336b9f40f7b961e9c54f94e37700073d4d26e, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 13
                let x := add(s0, 0x2ccd4cd53395c5ef4099c8d032097d33c9bbf102afc350f29d73391e1b2815ae)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x031511000251ec86feb38b5ab4e335f070b271df4c20979528e41d65384c318f, f))
                s0 := add(n0, mulmod(s2, 0x18e588324a9bbaacb42fa69e5d90a0c0e27cd16b941e34a60ff5df9a26c03af1, f))
                s1 := addmod(mulmod(x, 0x2642b5d8e16b953b070635775c8d3c9498357d6ad9bef2e7d99f03c10ea1f95f, f), s1, f)
                s2 := addmod(mulmod(x, 0x21fc313ba11c60e8e84ff60db906a0f031189b0b48335c4221f909aef836c133, f), s2, f)
            }
            {
                // partial round 14
                let x := add(s0, 0x06066582c016122a7f718be9336aab939b32cecba5cadf998c32852fbd3c67eb)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2d3562e3d4b42bc6890b698cc6ab89f7311298bcbac6e4e9f2f4d93d06dae151, f))
                s0 := add(n0, mulmod(s2, 0x0a74ef541d360e842e3e0b6ff7e5c7c77934a5f67616f01c189d886dfd2e0808, f))
                s1 := addmod(mulmod(x, 0x140564b53e0a812ac3983d6e3b433afa43f434087d9e754967c2c9b1b02caf8a, f), s1, f)
                s2 := addmod(mulmod(x, 0x14709e32d98ae4cd18b400181e71ab9759c436c8e83fa6993adb6f2db6bba9d0, f), s2, f)
            }
            {
                // partial round 15
                let x := add(s0, 0x1da9873ad8b1439b0f089146fa84755247058ba96306472759a5d7570ee96a29)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x0734b2366c59e394423f179e1266dd392372db4f2dba651f4a619a4b52bdc010, f))
                s0 := add(n0, mulmod(s2, 0x11fb2d705c94b08d5ad3e3c5fb6629abe963ed92913642c7d02d7e71088fd2d4, f))
                s1 := addmod(mulmod(x, 0x27d03abf5c1f290e5d715eba19371050ef6eb7f78fd84be834e4cc3618059484, f), s1, f)
                s2 := addmod(mulmod(x, 0x13ed9e9e6b452df27fb3353cfc2cd63ebe817f212a39c6a8bb9b441ac1395861, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 16
                let x := add(s0, 0x184ee817dfb8eefc50d06c4c63dc247f1a750a5713998c53fdb03f954f63a10e)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x1319c51cf37aaa10246cdaaa04a12e88795de4452604263a7c5b79ab99cbd23c, f))
                s0 := add(n0, mulmod(s2, 0x000bca25588d187b7f9dad839f2c8cb526a4cf444eebbd0e715b6cea019ac3f2, f))
                s1 := addmod(mulmod(x, 0x1d837ea0341c5964181226874b923cd01a069b493f02f7a3c01be23cf51d593f, f), s1, f)
                s2 := addmod(mulmod(x, 0x1b41ce9ed3634cbd42c427ce4c5c83774149e2a6dbd25f24012090db7de4e7f9, f), s2, f)
            }
            {
                // partial round 17
                let x := add(s0, 0x00abaf81fd3cbe5c354e900b5b305051890aa7d5477b6ee964250d18826cdcdd)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x0671f0e3b674ae7cddc790ecc4e946f4bca74b98b78a127c7b56bd6673f1ce1f, f))
                s0 := add(n0, mulmod(s2, 0x019fc073797a39b272e40cd30615f55fefeb682c1ac14143071d0449a5426e4e, f))
                s1 := addmod(mulmod(x, 0x017bee47d262a497fd1f7c5c6d5a7c70fa4209480bf5d97311c5096619e9fd13, f), s1, f)
                s2 := addmod(mulmod(x, 0x2073cff92d3141b480763539cff2978a4c7944721cc937ba00cc8527274471e3, f), s2, f)
            }
            {
                // partial round 18
                let x := add(s0, 0x18dd9e94f0a15f041ab8da038a7c3384799f18da930ccbde5ec154ee29231724)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x03bd7b3e2c1885877f43182a55a91d48f9c58d152e730fe2c7aa46b1fa663baa, f))
                s0 := add(n0, mulmod(s2, 0x226ebc9a538b5bbaff128edfb9bbf5fa0ceb100719a14c8dfed9ffbbbad9b6b7, f))
                s1 := addmod(mulmod(x, 0x0d395f0b08b9fede0373a06e1552c0e634a49572af1d830dc6e394e8a5d3b21a, f), s1, f)
                s2 := addmod(mulmod(x, 0x28242439b524540a30d49b68e19e31ba5284bd3bcf1e0f2f41f77d5331f99ffa, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 19
                let x := add(s0, 0x22a9db02cd988f336b6ef109f51485f3280bd3c708702c330d28b6f3f427ecb1)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x0370d6fa19eaac142d2de034801ab85e0b457e129e91f929754b48c6154d4df6, f))
                s0 := add(n0, mulmod(s2, 0x09a16f573b3280f390762abf269579eaa37939bc0c753feb0a2b2e0bcbde1659, f))
                s1 := addmod(mulmod(x, 0x2228e360fb5b162b496ac443f98127ee3c0021a690b71b268d99981368231d97, f), s1, f)
                s2 := addmod(mulmod(x, 0x07e42c2ca633d2c49fabf83991476d209431e34d8032b6a1b97675f3c567f944, f), s2, f)
            }
            {
                // partial round 20
                let x := add(s0, 0x1213c545a1f6533025f8fc5f1e17f97cca1bd2b8c410fbf78079ad2b27b0288e)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2ce12d7269663770c3cab85a6215a32eed35fda1d8e9d753a50fe96097724a9f, f))
                s0 := add(n0, mulmod(s2, 0x03d7427704c61e2009eeb9b1b45a0125084bc4daf70973a7ba0b2231815b15de, f))
                s1 := addmod(mulmod(x, 0x10f8abf0764185861c1267fcf4b4b33ca096fb4ddc4626732d86921e553e69c6, f), s1, f)
                s2 := addmod(mulmod(x, 0x17ccaf6f26f7267a025d7cb456e3aeb251a1a620aaf6568a5c95644c7c5914cc, f), s2, f)
            }
            {
                // partial round 21
                let x := add(s0, 0x26e9635f4d46f26fba8dff00a1aaf37861f712963723b47054fc6e6c8780d977)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x063bb306b96310051385c3ce00ca820ad0e3651a6e55754d59de6df28cea4d51, f))
                s0 := add(n0, mulmod(s2, 0x1f761ee5553c5e86f2c304a18095ab7403242e0b65e608bc920cf993a4169974, f))
                s1 := addmod(mulmod(x, 0x0dc5f00bbfd7c1d9a23c0e666859ba6564bcde8761b45717cd6bdfc09de4e8f2, f), s1, f)
                s2 := addmod(mulmod(x, 0x06de511520e277b7df07c3536381c13eb44cf790a230abc391089760bfc40ef2, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 22
                let x := add(s0, 0x2dd744e809ecd0e7670257249369e2d8fa22efd5aafb0f2e79d2f8c2559728c4)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2a134348c8660efcf9ef54863e70528a1fd4481b50a1fe21f24a8c06e10cca03, f))
                s0 := add(n0, mulmod(s2, 0x0aeb5023bbb9a64c4bd80089e99edf8ed5f6f1ffb63a7dbba1b33520bcfce37b, f))
                s1 := addmod(mulmod(x, 0x141a6d0810366ae225ecb5f0bfdc9995406c5960ab26155836fc51fb7cb933d1, f), s1, f)
                s2 := addmod(mulmod(x, 0x09d2ea05ef54dadbbe776f404dca6626cc0b2539990bc0b8bfe87497f1e2c5b7, f), s2, f)
            }
            {
                // partial round 23
                let x := add(s0, 0x0af00b5af30e88a3da0bbc526cceeff2c5230ee59dfe69236632ce3ea46b1561)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x1e56d244a8e41be5d104d5f8ef70891d22d4a5432441bfe8ff1a16e91719cdde, f))
                s0 := add(n0, mulmod(s2, 0x1d4f020c57c4f14aec908b2f99b5c4fd5e09447fa85c2fd68ba4d5c5f50c7b49, f))
                s1 := addmod(mulmod(x, 0x0763911a3a92a4f0e09f4e14cd03398d8d82a1e09db80fb0ee1e833764c18fd3, f), s1, f)
                s2 := addmod(mulmod(x, 0x12857275be2fe6b9ba2ec68f9061643f1fc5d9a2c5e47e55684366e54b302946, f), s2, f)
            }
            {
                // partial round 24
                let x := add(s0, 0x0393b7620d78da3651fd18b966d0fbac0f187233e4a9b32f47edc8db1b427e1c)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2ed11ccd2e2e2376655ffe9a96c4b81adc0a60353c5d83d4d0ebf50d1bbf87c0, f))
                s0 := add(n0, mulmod(s2, 0x03e31de8958e82645b320d5e3e966ef4726d5b1c2cfbb4acd288a21543c6d594, f))
                s1 := addmod(mulmod(x, 0x11e880dfefdbd08858ae890046533d58da28a608d7e905366ec2ca4a36e71963, f), s1, f)
                s2 := addmod(mulmod(x, 0x1835b275deaed2d00704a9c3cc21ab7a44a34662978d53c190dc25e969a507b2, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 25
                let x := add(s0, 0x078941b8f2fa2025cd8f72fb3af64abde9e52f4dcc331c132e0872ba288cfd54)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x068b75315e25ed4ace5a4a9480e1d82ce5d44f76f1324240419f372ff8d3c3f5, f))
                s0 := add(n0, mulmod(s2, 0x1b7ef7d04aec73d62b052d2ad12b92a4268fccd795c839d698ad3b22823274d1, f))
                s1 := addmod(mulmod(x, 0x28c0c848022a90606f6193ff5501b57216b670727f4b8efcc240d30bbaa9f03f, f), s1, f)
                s2 := addmod(mulmod(x, 0x13bda49296cbcc51686a7bfb1c39f3f254370985a16660efd6e5d82d4f068e1b, f), s2, f)
            }
            {
                // partial round 26
                let x := add(s0, 0x0d0c396d574ccda3d9838a319307b9cb23c6da24708c9dc752b3ac7aa0c01754)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2e7987ea8204389d11eb10b34265e378a945729f86c3e0e2fd38490d3a594141, f))
                s0 := add(n0, mulmod(s2, 0x0826d4a2324ad3aa4b2b45c10a190fedef702aeffda3226ce5415fffd03935c8, f))
                s1 := addmod(mulmod(x, 0x002dbeee85eaeaa9fa3675ef541c9df7bb964a85435c3b59685f93b434036ded, f), s1, f)
                s2 := addmod(mulmod(x, 0x227ee7a945edaee6919418ecb3279b11e6fa44f5f5c5abfb966a4be599cb86c7, f), s2, f)
            }
            {
                // partial round 27
                let x := add(s0, 0x2d2d6c06688b5d61a28ac65fe5ceb6fbacaeda447e8c26378e4f1174fd0e7f0b)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x1d0a6d1a9519877805ac90d696faf2a5ffadc23986de8c698d541471c7244220, f))
                s0 := add(n0, mulmod(s2, 0x2208aaba508ae816da4f333b7854fbbcd10eea1db284ec3e9f4de02b25f6e9d4, f))
                s1 := addmod(mulmod(x, 0x28a58901035b2c99e36a7d29b587a215c9e59268e2f8e01a175720971ccf04ec, f), s1, f)
                s2 := addmod(mulmod(x, 0x0112f6d8d42b0a0d123a07865ca1376df317a2a14ffc0191226f38a8adfd6238, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 28
                let x := add(s0, 0x213cc690d85f0d7b12cede4e87721ccee84a0cf9140f100be64b937e89ee2b75)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x08c6eb19c016d1833174dda182d266d5c727f97fb4d01f1daf906b6d3c6e2308, f))
                s0 := add(n0, mulmod(s2, 0x1359d2d6c8b5a116d0b38b95f9c642df75b1be9a48c8698ecfea9103f73f1879, f))
                s1 := addmod(mulmod(x, 0x10c5052ec67ab9b6a467c1cc1878d91aaa07aacf7725f8a5ed42b699c4af3ca7, f), s1, f)
                s2 := addmod(mulmod(x, 0x0583c4d292d54f3cdb708803e6338fc6afdb188d5d4e9f060193823684c96c75, f), s2, f)
            }
            {
                // partial round 29
                let x := add(s0, 0x183c7f47bab034a6791607eb5507d2fb77c3bef7e1eb8f9e660ed49d6fa835a4)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2d94a1c55be382151a4054c5b96322e7bcd1fe2b3e076e16ee2c18bfc06f57b4, f))
                s0 := add(n0, mulmod(s2, 0x15e3402fdde8770fb997369579c1b1703ef77c671927ead80dbc64dd2211c3ec, f))
                s1 := addmod(mulmod(x, 0x185be98784817f22f7b21e6b867d5a71b5000bef8bb902eb302677e20a727be3, f), s1, f)
                s2 := addmod(mulmod(x, 0x18db4321c721c03666ed8927c89890aa8aad1b00c054547b5ca14cd94de467b6, f), s2, f)
            }
            {
                // partial round 30
                let x := add(s0, 0x12d38aca7d7f2999acdaa7afa470dbc0d014f994ff8a425dcf5d709b4c5f8891)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2a852b6247f5d61f0c390b3f3d799188528849bcd2cd0aff4eb2134a039b5126, f))
                s0 := add(n0, mulmod(s2, 0x2510aeed51b7f506e65fb9a18ee0124aa5276f6de1cd771b165930204da58f22, f))
                s1 := addmod(mulmod(x, 0x0f2074a32eb8260fb5bd3a236f03a47b47b7fb54dcad1d7977d6486513bab5f2, f), s1, f)
                s2 := addmod(mulmod(x, 0x2f4c69297866bd45a8270e19941926cec3531c9e12c4c2c84971404bfa044090, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 31
                let x := add(s0, 0x05faa348214268d0b5c54ed0cde8c83a4d79fb15fa94b65a1b01ea1c50757625)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x154668727d2dbadf05d083a65093c0d0e92df5fd5f3fd75e9b792c562a37473f, f))
                s0 := add(n0, mulmod(s2, 0x1e6ffc5d6a1ff5dc4fd77fc5ab5c8c4e8d3e2e375bcd1194a91e5b0f7b13cadf, f))
                s1 := addmod(mulmod(x, 0x2cf1a1d7c44309109d75acbc9395cb8398c8b2d428538571fafa389da29990c6, f), s1, f)
                s2 := addmod(mulmod(x, 0x140fb39a89f26f6d87cf76cd5ce8da47aa5d8a023e24cf016ecf64cf793c9880, f), s2, f)
            }
            {
                // partial round 32
                let x := add(s0, 0x0e8dd67f884a87588287f3ab55972a7496023a43f8da426ab59bf676425b6d4a)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x1289d13d58a17b5bf0712b201fb3cddfce2c16dac159990b8298a93a8589f9e8, f))
                s0 := add(n0, mulmod(s2, 0x0f45cf974d2c9edb5781e8d3d207adc8370cf56bc5218749610920fe98b2db2e, f))
                s1 := addmod(mulmod(x, 0x11909c81a16518046b79edfd24f5abcc585a81d1b333568b8687a1c9eceb44d4, f), s1, f)
                s2 := addmod(mulmod(x, 0x2990b23c81882f7709f3b891a0e3da4d6917672f2d5a1041fd7bbd6792330d16, f), s2, f)
            }
            {
                // partial round 33
                let x := add(s0, 0x0810d122c011c8830f48fdbe9b43231db5f2938aa501e15b0ace836776247e20)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x0609551b14716ca3cd5560e0821e7285e0a083ea9a16dc102ecf461e4aef7277, f))
                s0 := add(n0, mulmod(s2, 0x0c8c1abdfab99d03fd93dced2467354b6175de1755f4f93dc0880eaa08d03f77, f))
                s1 := addmod(mulmod(x, 0x138bd098c4923b9fbd02f33f8bec6c730db3fed298ec09f78a7a55d08f2e0b10, f), s1, f)
                s2 := addmod(mulmod(x, 0x2e61e4bc021630114673f0f77161ae55dcd0b45ce07d9ae3f21bb5a3190f14c0, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 34
                let x := add(s0, 0x127e998cf30f76cc5f9b0e0359285a5df42549d1702a44ba117474f02632c618)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x0124860913e3df8f65a9c4060ce3297c626abd1c22401c905ddb408260d8e910, f))
                s0 := add(n0, mulmod(s2, 0x013807f89c394a133ec104804d955cbe125f24c5701d98286c6ac8b7ed052ec8, f))
                s1 := addmod(mulmod(x, 0x2e88d1a6938f0788132aa9eeaec08d2f59aa444050c8f4c4e85578abb0fc2fe5, f), s1, f)
                s2 := addmod(mulmod(x, 0x01f3d24f17cfc6050a0cbf64e1f1787e2257be3c3ba607c2e8fcc1f26abf3104, f), s2, f)
            }
            {
                // partial round 35
                let x := add(s0, 0x03f148ee71169a9f22c37ad1338c285c9dd0113aa82c26dd2fb73e92f22b7a5d)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x1fe1cb0e2ae169f83b9d4f133d41fb5b3fe6c76a82a916bfd9b62f82f0f8d0bf, f))
                s0 := add(n0, mulmod(s2, 0x0ef79351229409cd353329221229827e19946f3d8d1c48bf5e3377f9177071f3, f))
                s1 := addmod(mulmod(x, 0x18fb2e46fc1b90fe1c4893ef77a9d111507551883127860e89088608373beda9, f), s1, f)
                s2 := addmod(mulmod(x, 0x077afe2579f42ec14c32ef0761e23a3cc0ad6263a68c5cb61916bd57120d1868, f), s2, f)
            }
            {
                // partial round 36
                let x := add(s0, 0x1fcc2a3ecd83418b7c04e83c213d6c53c03448efff4928365287f12883f12f0e)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x079769092daa5a752642c04ccf8a6ea54e2ac9836fdd65d248b186f1490b7b99, f))
                s0 := add(n0, mulmod(s2, 0x1d8bf229c19968f0254eb6e09c5c8bfd67eb9734606b676b663c76cf76bab4a5, f))
                s1 := addmod(mulmod(x, 0x2a33b7d855e7fe55f93556e49e4b37737664f14236f17256428f29f6ec1bddad, f), s1, f)
                s2 := addmod(mulmod(x, 0x25b0331d7e2b15af4ec161c86e84ba6ab2056077e7aa7536340dc3187ccca8b2, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 37
                let x := add(s0, 0x1dac70a36e33ebca594a8830eaee643a5fe4edd016cc05119244e5eddb27be90)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x0762098f5fe26598ccbf45e4810211b0ffcf8ccbb92c16e2f4f13f22342474e2, f))
                s0 := add(n0, mulmod(s2, 0x0e234d720d70b2886d0da4c007b1bda42362e144185c70716dece2b6172c2514, f))
                s1 := addmod(mulmod(x, 0x1d82bedccd2bc8a06e3742e720b7fec2ea72182f11c0c60d135c811152aa4b60, f), s1, f)
                s2 := addmod(mulmod(x, 0x0480064d4b3eb0ada5e9a3e7d05930b7c3397fd6b94d481314bd1c690a17c979, f), s2, f)
            }
            {
                // partial round 38
                let x := add(s0, 0x030ec7605dd5869a17ecb0b25596d75efe68ce5c8b4585a2833ec62d0608b202)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x10a892763b3cca9ef7593fbb1140edc8c8e4580568560cf41867f7464fb0c11a, f))
                s0 := add(n0, mulmod(s2, 0x0b5ec64548ea841ac921f9b2553680785978b315667ae4714dde4cd7f4de8b91, f))
                s1 := addmod(mulmod(x, 0x10554aca4e348e5949761bd7131dfaebd78010edd030e1a9ce3c65c9db931d46, f), s1, f)
                s2 := addmod(mulmod(x, 0x15be66f38d86b0998b93655462b1f475b9be9de306e150d4ac648fab3db0cff6, f), s2, f)
            }
            {
                // partial round 39
                let x := add(s0, 0x0ef0a55659c6c606355a3e0c1eb400b83cf39c44544b59f9d7391f1920dbde1b)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x176ad3600fd3491182d182957ffad01bf6c26e9d4ab0c23caaf308e427d3dbe8, f))
                s0 := add(n0, mulmod(s2, 0x2b6f355b3dbf65f09335001d705ac125e3beb20f4fc11bd3ce82b5cf0af2e6f2, f))
                s1 := addmod(mulmod(x, 0x01c85c06a6d5d40d81d7c89edefb32d1a8448c51288fa296b6de9ff788c77451, f), s1, f)
                s2 := addmod(mulmod(x, 0x20e1e876c4746a0cbd9a51d76b2e25f82361c389e43f7d1f51a70aaac2460d79, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 40
                let x := add(s0, 0x2ea57e170f7d89c2034bd8fcc3e48ced68cca812b5ac7eeee6f30443f2be21df)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x20e46219f684186d2a024b637bc35a29ee3b08ce737701392d987dda9217fa08, f))
                s0 := add(n0, mulmod(s2, 0x2ea7279db9f2aa0f654e987907277c24480766367a8bd90e28be0f2ed6091367, f))
                s1 := addmod(mulmod(x, 0x136be2a7f18924c9362096d472bc75ca0969dc077c9171b1641be95091780f74, f), s1, f)
                s2 := addmod(mulmod(x, 0x1ca2033501baa3f73067c4300fb0f51119ed5736fbc8f1f6c924baf0df5a0e9e, f), s2, f)
            }
            {
                // partial round 41
                let x := add(s0, 0x0387db6cf8e365c34aa496466ac8127813e1fa2bc9c9084bf95214811b31ca45)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x0a82f199c2505277ecaa75e495f34e3525824f7a4a9d9fa1da810832b48a50c7, f))
                s0 := add(n0, mulmod(s2, 0x0ecf10485307b4bae92fefb0d7f7782a9f37a2722e7ed9eb7925a2dea580b7d5, f))
                s1 := addmod(mulmod(x, 0x07b642138dfd6a6dd12aa22f08a8296d68615c8478f13af16aebbbb339a3936b, f), s1, f)
                s2 := addmod(mulmod(x, 0x1d9dda43a25593ffd2256d34921fb86ed70e760ba76d61e9cbc3b6dd0f1a2150, f), s2, f)
            }
            {
                // partial round 42
                let x := add(s0, 0x1c17bcb60cad114daa86b7ab0faf2f9e53b4f1590d72ad49598a1c9f631762b3)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2f1af228520c8b751dc91136c91c6bccd5367eb08213d392958ce2fd3d7d2fce, f))
                s0 := add(n0, mulmod(s2, 0x1fecfe833ad540455c6d6c1ab3de4abae61ada625a1a2b6b18551a45a6cde123, f))
                s1 := addmod(mulmod(x, 0x18fc8e608c735b2b3b0d7583460227575657ff8a77abe637bdd3ad28e4a23c88, f), s1, f)
                s2 := addmod(mulmod(x, 0x28f740bc1182e9706ebf03cb3f53aba8a43ce0b618783a5586388a7547faa815, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 43
                let x := add(s0, 0x1958056f36be3ded17384bb3a059357846f2b30b01f0337c1e1c2b704d3ea0e4)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x047998cc0af5a26b94ad301e4b998d29e960a4851cfd13822bed35b7146966a4, f))
                s0 := add(n0, mulmod(s2, 0x1b5f1525b31db911dda43e415e1b9a3a9725c7b52e880ee130a14a692b777b70, f))
                s1 := addmod(mulmod(x, 0x275a83fa5d19b4535f65e965a90eac9bf770ae9bd1d7b1af945fa57ed5c8de6e, f), s1, f)
                s2 := addmod(mulmod(x, 0x2e8789257ed2cbcccb430568e49bc9dc2a563359808c9897ce3e40a6f6a27aa8, f), s2, f)
            }
            {
                // partial round 44
                let x := add(s0, 0x2de99b3e77de42ec6e5975d4477ae96d00b23bf9c6391e595529e0a4021221fb)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x0927f46cfe80feefeb2721a4c09e9d17f60c34500dcd6e41e2925a39c8e2c7c1, f))
                s0 := add(n0, mulmod(s2, 0x1f868ae04832a5dbc37619bfe6ab6a97fd8fb2cfbc1ecf9e0e484bbfe7698101, f))
                s1 := addmod(mulmod(x, 0x09d7a11e27d2f53109b73f745b2defed65d94ba80f308fb19ce6d56c9b45eff4, f), s1, f)
                s2 := addmod(mulmod(x, 0x282d857cfe8da3b5104e1c2823fb7c5b9a7b25924fda5995b0c351aa2b879dff, f), s2, f)
            }
            {
                // partial round 45
                let x := add(s0, 0x2d2131086c3bc3418dde3237acaabb24b27e9e2cbfd7a9ebf52bd612688b3527)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x20ba8a9fcec815b13f349ff830ae663b27576e135c0744f6987fb0f6ff49c217, f))
                s0 := add(n0, mulmod(s2, 0x11b6afc91e32f1ca4589fba12e657d226d57b471ddd2ab1b66a8ae4dcbfb136e, f))
                s1 := addmod(mulmod(x, 0x2e666402ac9cc588316e335c7d93db344788eec2c72ddf3f908141736cebc3be, f), s1, f)
                s2 := addmod(mulmod(x, 0x17522e0e9e64f795a202a110e283faad7057aec5c9ed9a1a74920f2794f18595, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 46
                let x := add(s0, 0x0ae349869aec39bf93f8b2cbd631d4baf910de6d1712142acfa2b82dd7ec01fa)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2d2ed17f7a1f3ee9e20b470cad4cc7319e6adb40e2ff24b7878cb9878edbd3b9, f))
                s0 := add(n0, mulmod(s2, 0x1a81efb19d7e1edaa96fa276e89e85d08f75e54a8136f4d73c937da16c7bf9f4, f))
                s1 := addmod(mulmod(x, 0x27ff57c1ca847e57210a7b44e52e5630f299c5f451c7a0d515a16bb3bd33e237, f), s1, f)
                s2 := addmod(mulmod(x, 0x1c1a8e22230abcd13c5be96031bfa167840d117b3c6a5a0a11be26a7f5fb1a94, f), s2, f)
            }
            {
                // partial round 47
                let x := add(s0, 0x209df7f7923cb342ca83896920e95f9f11c4729970172640b000430eca179989)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x02a1c3f15d4927c843627a9cd533e4250d81e7774d2c32b59d5836f9c19a5657, f))
                s0 := add(n0, mulmod(s2, 0x2ddbb7239eb904d81c52499b37cb4be1af0373a10ac112e185acb219899357e4, f))
                s1 := addmod(mulmod(x, 0x0dff198393085a754e0d6faec54be81d8edf8bc25edadab48a86fad6da0afb60, f), s1, f)
                s2 := addmod(mulmod(x, 0x10d50c2473146bbc76275fcc589d038dec8db28728789f28b6d5f504bd1645ca, f), s2, f)
            }
            {
                // partial round 48
                let x := add(s0, 0x21e79c2d6c42734a9a608dc58c35c137517b1e64a5d5767fdddaa1a12efade88)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x061e8328fb5593f92a53dfd40e1022e6231ba45948506282536b08b4476c1538, f))
                s0 := add(n0, mulmod(s2, 0x1b589243847198ded90b644bee31ac58067debf3f07d3c51cfa5a0dd9f6d9784, f))
                s1 := addmod(mulmod(x, 0x04b00c0da1f851e59863b053bd4c6087190f0bdcced99d5ce6f67a420a3bd1f7, f), s1, f)
                s2 := addmod(mulmod(x, 0x239941a46c2b93d9126a70163009a7ac27f8a8d42e35018b3bec8cdcb5ddfd67, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 49
                let x := add(s0, 0x049c4e33e7ccf5ad5ebd5d0794ade154e86af76537ee5ccfa237a262c4e467ba)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x204f26ca7993b03ac2c35377cb0a3712bfc9bc3ec0bfecb4e87ef6814acf2ea2, f))
                s0 := add(n0, mulmod(s2, 0x085aff9c7fdadba039d832d8be165a1e5747cf7308d515e348ef117e926d721c, f))
                s1 := addmod(mulmod(x, 0x249042a8dc111f27c4ae9db044c0b0b3f10e57d05e093158efd375df00ea2068, f), s1, f)
                s2 := addmod(mulmod(x, 0x06e799bcdf2b4a74542854f3029803e2f84550665203327b3e0825977413e96b, f), s2, f)
            }
            {
                // partial round 50
                let x := add(s0, 0x1869d4e923fb31e8424a16c269e46ac49254c3d05ff35022a76b98b11f8b8b33)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x1cb3caed4bffb6aca9f4d2c002921bc3fffed333cae12085c612496183b87996, f))
                s0 := add(n0, mulmod(s2, 0x0b47e9755fae480128a128bfd4faa6a3dd6ea03cab566889dcd99e84d310d51c, f))
                s1 := addmod(mulmod(x, 0x0c7e4cea365c2061920a0c9fd2c360a6506293bc024fd1ca3f0bb730da886a4f, f), s1, f)
                s2 := addmod(mulmod(x, 0x21da1f701bac77bcbbaa30d964d6f6f63dbe1b20d9d6988c8dcd7ba4187215df, f), s2, f)
            }
            {
                // partial round 51
                let x := add(s0, 0x23bf80f538756a283d8f04719a8b6e028ddedeb95e2fa971a1aa002d34539385)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x09ae612e8ba1ca1370905fb67899d10db86b47bd19965b6edd1a9486e3c6cc55, f))
                s0 := add(n0, mulmod(s2, 0x262e1e0b56cac47fc150f284491190e6aab75445b0c99373fe1f7a0e3b95cf3d, f))
                s1 := addmod(mulmod(x, 0x234bf4a7dce7587c2c87c293e3bb7c9e2a7bfa5f29fd4ddeaa5d3f67491d34bd, f), s1, f)
                s2 := addmod(mulmod(x, 0x2f6cbac694c886b02d0a527cac744fb658d2690e213d7432eee67f6cb69f70c2, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 52
                let x := add(s0, 0x26cde2d63e1b586581f632ce4c4fa2efc226bc5cf18d65c5525a8fcc5066fb94)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x22accb18b7c49b4b7bb8c9fdf78b7aded52aa1842fff818d9a3300876dec3ad9, f))
                s0 := add(n0, mulmod(s2, 0x081e2f0652f898c6d659f22d2c77be302eabd9182a0b3d3cbf623a1df7f8f2fc, f))
                s1 := addmod(mulmod(x, 0x12c0a25e70d006eccea3ada75d669b8c534b962890f3ffc016b3186ad675b935, f), s1, f)
                s2 := addmod(mulmod(x, 0x10ef9c23848128cc2fd6fc869df24d7ab56efd349edd56f49f8d4f2381df3259, f), s2, f)
            }
            {
                // partial round 53
                let x := add(s0, 0x14076b33136ec0e1ac549638a4b902ba5d6ebf052a8f14804256e47cf2c2f04b)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x2161cd280772819dd4a81262b71df1bcc2c1d41b9491e0620bda347962b240f0, f))
                s0 := add(n0, mulmod(s2, 0x2cebb0ae5108318eb406590041b5248292533364f799bc41b7f4fdd12cb8d38a, f))
                s1 := addmod(mulmod(x, 0x2b2092f86b5979a7fe4f7c22d9561f3bf2852283a656880fb759e08709a0a62f, f), s1, f)
                s2 := addmod(mulmod(x, 0x1566b3402d774b8c08146188425a442450cfc900cf643e7382b2d8507a065fed, f), s2, f)
            }
            {
                // partial round 54
                let x := add(s0, 0x2cd8fb137caa0ed0b658a8fb3b7568185e987910e8aaa40e0db02a734e03c42e)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x11a316aa31607f268fb4c56d6c57ba01627c3635fccf8d3d1a163e601d1a0173, f))
                s0 := add(n0, mulmod(s2, 0x0de7ee069c934256b782648b560e595408a5e8434644609152e353d9c2874e44, f))
                s1 := addmod(mulmod(x, 0x02d36f4029245704cc84df0297708c5e5845c36ae706c72e67128b8949eab1af, f), s1, f)
                s2 := addmod(mulmod(x, 0x01b8cc326b5ee160f53198c217fb34e899bde46cd82dabdc284d7951d546f858, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 55
                let x := add(s0, 0x024562fc799792e21a0c94cbb88e1a43b297948049cef86c17d04a0298d793b8)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x27625da0f73ea07110689fb2187b71694cbf9203fd4ddf8a96ece85407550ebb, f))
                s0 := add(n0, mulmod(s2, 0x1cd8338a3e5b1ad7cdc0da581a6950f6dea349c3edda06cb99ba025b94e4790d, f))
                s1 := addmod(mulmod(x, 0x05ea02d65b209f6da763856c94b6438c78a8aed8d3e67e877a10a84072741a56, f), s1, f)
                s2 := addmod(mulmod(x, 0x09f7cb68d4e388f85366cfcf284a895d8b6250ced627e810817743ce03330a55, f), s2, f)
            }
            {
                // partial round 56
                let x := add(s0, 0x270aec6f1b7b1a1a241b2b0b78f713f2aa23a25cbcbe5220eae939775fc7295c)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x18c6230ddc0f896827b043f5e58dbd1aec13995a202e4ebcdfeb969e9d5c1212, f))
                s0 := add(n0, mulmod(s2, 0x073a6114b997285e1a91c0a0fdccdaa8452e4f07bfd2e1a10578232096db6dcd, f))
                s1 := addmod(mulmod(x, 0x2e78746340b2a6d222c6a1fc0838adf5fe013f39b1660ce7a3e7742b2f37be7f, f), s1, f)
                s2 := addmod(mulmod(x, 0x07aa27e7150baddd06303ad8e5e4bf4249b7ea846553def28e675259d3e5c851, f), s2, f)
            }
            {
                // partial round 57
                let x := add(s0, 0x1a093a3014147bf0bac4e3c917c367b95f7955495b87549ecc6ce7f96d7087e6)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x0b66fdec210ea4eabf623d2712cf4d9fa90273ccb4643f680cbc98345715ead8, f))
                s0 := add(n0, mulmod(s2, 0x2fb6a29d9f394a589b633b8a4d6be51c9c0601ce0b140be641acea41c49aa5e3, f))
                s1 := addmod(mulmod(x, 0x29025cc66fd041c4fc845e9c1c2cd1288569fb243d049bd675a69dc889b2ce2a, f), s1, f)
                s2 := addmod(mulmod(x, 0x150963f0aca9bcbe4126214ab9c627a6f7ed731cfa695168b85d534b17be3f48, f), s2, f)
            }
            if zero { f := 0 }
            {
                // partial round 58
                let x := add(s0, 0x0dcebf0a0455c0d2b7cf2b4a674258af44a114be3a162795ed39938193b79f06)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x0ed59780302257663f72c1bfc6656eb7b5bca2e47bec0d5798a08a32a61a8a65, f))
                s0 := add(n0, mulmod(s2, 0x07e19cb8a893369b3d30ae188c767f391c11888a3000debfc8d30c06143cc084, f))
                s1 := addmod(mulmod(x, 0x0600c7d2b6946345e5f1eeeafb5eb8ec2b6ecfe528d2c052cd860afb4a3aa272, f), s1, f)
                s2 := addmod(mulmod(x, 0x0596083b6c972bc13022a1f33d6523b4773f2cd0a480e19ea0125119f0385705, f), s2, f)
            }
            {
                // partial round 59
                let x := add(s0, 0x0910adbe751bb9038b98054eb027a8b71f83ad86ad8c06255d1c0c8d77a448f8)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x210b5c36f27a07d97f98b9d8663d85db2e64513099a8e1ef6db21043631e24c4, f))
                s0 := add(n0, mulmod(s2, 0x13bb2764bf1475cfc7bb9f3d563c5cc201c2489874e9159326a8f4930b7883f9, f))
                s1 := addmod(mulmod(x, 0x202cf557d625c26080eb082862a76757287872b181e89997219e4b7576e24d30, f), s1, f)
                s2 := addmod(mulmod(x, 0x0e561c3f8bd4f76e76d49e97142d220601fbc5a03d905a4728ea1f95fd8824b2, f), s2, f)
            }
            {
                // partial round 60
                let x := add(s0, 0x209a5c2333bdb226479c47dc0e045edb76cb46c3b886f5df3b9796842f174a8f)
                let q := mulmod(x, x, f)
                x := mulmod(mulmod(q, q, f), x, f)
                let n0 := mulmod(x, m00, f)
                n0 := add(n0, mulmod(s1, 0x0de20097480e7555471785de07bd9809d57dd859bbe827307c33ae9ed7890597, f))
                s0 := add(n0, mulmod(s2, 0x072f2a6287fb984bb810df8c5788eebcfd2825613cb72bb80cde8edd76d2e97d, f))
                s1 := addmod(mulmod(x, 0x2969f27eed31a480b9c36c764379dbca2cc8fdd1415c3dded62940bcde0bd771, f), s1, f)
                s2 := addmod(mulmod(x, 0x143021ec686a3f330d5f9e654638065ce6cd79e28c5b3753326244ee65a1b1a7, f), s2, f)
            }
            if zero { f := 0 }
            {
                // full round 61
                let x0 := add(s0, 0x18d1db85bf7812d2cc6e761ce8b778e46a8fb6dec2b640692e39748ee1857cba)
                let x1 := add(s1, 0x072c1bbe5b21fad79ea9520d9d76706713b173b7293f9c31eb5e88b77c646292)
                let x2 := add(s2, 0x069b898b636f3281d5e49d4e543e4134f3480e62c8a20d4c846db06afaea7a34)
                let q := mulmod(x0, x0, f)
                x0 := mulmod(mulmod(q, q, f), x0, f)
                q := mulmod(x1, x1, f)
                x1 := mulmod(mulmod(q, q, f), x1, f)
                q := mulmod(x2, x2, f)
                x2 := mulmod(mulmod(q, q, f), x2, f)
                s0 := mulmod(x0, m00, f)
                s0 := add(s0, mulmod(x1, 0xa81a2d39df4ea14393d1ea65d461c5d40bb09579490b3c09a26c25ffac4903e3, f))
                s0 := add(s0, mulmod(x2, 0xbcbda6f8b35ee6071f08b900446c37256fa2643d7a17762f44c074731e367370, f))
                s1 := mulmod(x0, 0xba96ddd790c684fde2b43d99c7fde4e1a564b6aaae888f92a1cf2178ae0bd774, f)
                s1 := add(s1, mulmod(x1, 0xbf5105528f97ccb6758942ebb71a46d931392d15f9a7e7f3f55811d257b1fe26, f))
                s1 := add(s1, mulmod(x2, 0xa13d5d48a6b85a33c0222999ed930e548d2906ea0c8c02199450ad1170f89bfd, f))
                s2 := mulmod(x0, 0xa55d0d450bff1fb036506f88cabc0f745f6932bbf9878906fe0825aa35a1b1aa, f)
                s2 := add(s2, mulmod(x1, 0xa899ab820cefb0a2ab97e0228d2b06b148f39a07c614296a7d12c06798ee2914, f))
                s2 := add(s2, mulmod(x2, 0xaad0e762fa050c7140ab5111bc8662571edfffdc7430912b3ecd7d92ed25d5e3, f))
            }
            {
                // full round 62
                let x0 := add(s0, 0x1cfb5662e8cf5ac9226a80ee17b36abecb73ab5f87e161927b4349e10e4bdf08)
                let x1 := add(s1, 0x0f21177e302a771bbae6d8d1ecb373b62c99af346220ac0129c53f666eb24100)
                let x2 := add(s2, 0x1671522374606992affb0dd7f71b12bec4236aede6290546bcef7e1f515c2320)
                let q := mulmod(x0, x0, f)
                x0 := mulmod(mulmod(q, q, f), x0, f)
                q := mulmod(x1, x1, f)
                x1 := mulmod(mulmod(q, q, f), x1, f)
                q := mulmod(x2, x2, f)
                x2 := mulmod(mulmod(q, q, f), x2, f)
                s0 := mulmod(x0, m00, f)
                s0 := add(s0, mulmod(x1, 0xd87e7bacc080416d4c22301c55e31e3133e47dc1c2c4ac9ae64e1b939c4903e4, f))
                s0 := add(s0, mulmod(x2, 0xed21f56b94908630d758feb6c5ed8f8297d64c85f3d0e6c088a26a070e367371, f))
                s1 := mulmod(x0, 0xeafb2c4a71f825279b048350497f3d3ecd989ef328420023e5b1170c9e0bd775, f)
                s1 := add(s1, mulmod(x1, 0xefb553c570c96ce02dd988a2389b9f36596d155e73615885393a076647b1fe27, f))
                s1 := add(s1, mulmod(x2, 0xd1a1abbb87e9fa5d78726f506f1466b1b55cef32864572aad832a2a560f89bfe, f))
                s2 := mulmod(x0, 0xd5c15bb7ed30bfd9eea0b53f4c3d67d1879d1b047340f99841ea1b3e25a1b1ab, f)
                s2 := add(s2, mulmod(x1, 0xd8fdf9f4ee2150cc63e825d90eac5f0e712782503fcd99fbc0f4b5fb88ee2915, f))
                s2 := add(s2, mulmod(x2, 0xdb3535d5db36ac9af8fb96c83e07bab44713e824edea01bc82af7326dd25d5e4, f))
            }
            if zero { f := 0 }
            {
                // full round 63
                let x0 := add(s0, 0x0fa3ec5b9488259c2eb4cf24501bfad9be2ec9e42c5cc8ccd419d2a692cad870)
                let x1 := add(s1, 0x193c0e04e0bd298357cb266c1506080ed36edce85c648cc085e8c57b1ab54bba)
                let x2 := add(s2, 0x102adf8ef74735a27e9128306dcbc3c99f6f7291cd406578ce14ea2adaba68f8)
                let q := mulmod(x0, x0, f)
                x0 := mulmod(mulmod(q, q, f), x0, f)
                q := mulmod(x1, x1, f)
                x1 := mulmod(mulmod(q, q, f), x1, f)
                q := mulmod(x2, x2, f)
                x2 := mulmod(mulmod(q, q, f), x2, f)
                s0 := mulmod(x0, m00, f)
                s0 := add(s0, mulmod(x1, 0x16ed41e13bb9c0c66ae119424fddbcbc9314dc9fdbdeea55d6c64543dc4903e0, f))
                s0 := add(s0, mulmod(x2, 0x2b90bba00fca0589f617e7dcbfe82e0df706ab640ceb247b791a93b74e36736d, f))
                s1 := mulmod(x0, 0x2969f27eed31a480b9c36c764379dbca2cc8fdd1415c3dded62940bcde0bd771, f)
                s1 := add(s1, mulmod(x1, 0x2e2419f9ec02ec394c9871c832963dc1b89d743c8c7b964029b2311687b1fe23, f))
                s1 := add(s1, mulmod(x2, 0x101071f0032379b697315876690f053d148d4e109f5fb065c8aacc55a0f89bfa, f))
                s2 := mulmod(x0, 0x143021ec686a3f330d5f9e654638065ce6cd79e28c5b3753326244ee65a1b1a7, f)
                s2 := add(s2, mulmod(x1, 0x176cc029695ad02582a70eff08a6fd99d057e12e58e7d7b6b16cdfabc8ee2911, f))
                s2 := add(s2, mulmod(x2, 0x19a3fc0a56702bf417ba7fee3802593fa644470307043f7773279cd71d25d5e0, f))
            }
            {
                // full round 64
                let x0 := add(s0, 0x0fe0af7858e49859e2a54d6f1ad945b1316aa24bfbdd23ae40a6d0cb70c3eab1)
                let x1 := add(s1, 0x216f6717bbc7dedb08536a2220843f4e2da5f1daa9ebdefde8a5ea7344798d22)
                let x2 := add(s2, 0x1da55cc900f0d21f4a3e694391918a1b3c23b2ac773c6b3ef88e2e4228325161)
                let q := mulmod(x0, x0, f)
                x0 := mulmod(mulmod(q, q, f), x0, f)
                q := mulmod(x1, x1, f)
                x1 := mulmod(mulmod(q, q, f), x1, f)
                q := mulmod(x2, x2, f)
                x2 := mulmod(mulmod(q, q, f), x2, f)
                s0 := mulmod(x0, m00, f)
                s0 := add(s0, mulmod(x1, 0x475190541ceb60f023315ef8d15f1519bb48c4e855985ae71aa83ad7cc4903e1, f))
                s0 := add(s0, mulmod(x2, 0x5bf50a12f0fba5b3ae682d934169866b1f3a93ac86a4950cbcfc894b3e36736e, f))
                s1 := mulmod(x0, 0x59ce40f1ce6344aa7213b22cc4fb342754fce619bb15ae701a0b3650ce0bd772, f)
                s1 := add(s1, mulmod(x1, 0x5e88686ccd348c6304e8b77eb417961ee0d15c85063506d16d9426aa77b1fe24, f))
                s1 := add(s1, mulmod(x2, 0x4074c062e45519e04f819e2cea905d9a3cc13659191920f70c8cc1e990f89bfb, f))
                s2 := mulmod(x0, 0x4494705f499bdf5cc5afe41bc7b95eba0f01622b0614a7e476443a8255a1b1a8, f)
                s2 := add(s2, mulmod(x1, 0x47d10e9c4a8c704f3af754b58a2855f6f88bc976d2a14847f54ed53fb8ee2912, f))
                s2 := add(s2, mulmod(x2, 0x4a084a7d37a1cc1dd00ac5a4b983b19cce782f4b80bdb008b709926b0d25d5e1, f))
            }
        }
        return (s0, s1, s2);
    }
}
