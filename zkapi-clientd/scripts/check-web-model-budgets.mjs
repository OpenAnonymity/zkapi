#!/usr/bin/env node
// Refresh/check parity evidence by executing the real web policy modules with
// synthetic public policy. No credentials, network, or browser state are used.
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const [webRoot, mode = '--check'] = process.argv.slice(2);
if (!webRoot || !['--check', '--write'].includes(mode)) {
    throw new Error('Usage: node check-web-model-budgets.mjs OA_CHAT_DIRECTORY [--check|--write]');
}
const tierPath = 'chat/services/modelTiers.js';
const budgetPath = 'chat/zkapi/services/zkapiModelBudget.mjs';
const tierSource = readFileSync(resolve(webRoot, tierPath), 'utf8');
const budgetSource = readFileSync(resolve(webRoot, budgetPath), 'utf8');
const assignments = {
    'test/tier1': 1, 'test/tier2': 2, 'test/tier3': 3, 'test/tier5': 5,
    'test/tier8': 8, 'test/tier25': 25, 'test/tier100': 100,
    'test/unreviewed': 10, 'test/reasoner': 25, 'test/tier100:free': 1
};
const dataModule = source => `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
const replaceOnce = (source, original, replacement) => {
    if (source.split(original).length !== 2) throw new Error('Web module import changed; review the fixture adapter.');
    return source.replace(original, replacement);
};
let tiers = replaceOnce(tierSource, "import { ORG_API_BASE } from './orgEndpoints.js';", 'const ORG_API_BASE = "https://policy.invalid";');
tiers = replaceOnce(tiers, "import { fetchRetryJson } from './fetchRetry.js';",
    `const fetchRetryJson = async () => ({ response: { ok: true }, data: ${JSON.stringify(assignments)} });
     const localStorage = { getItem: () => null, setItem: () => {} };`);
const tiersUrl = dataModule(tiers);
const pricing = await import(tiersUrl);
await pricing.ensureModelTiersReady();
const budgets = await import(dataModule(replaceOnce(budgetSource,
    "import { getTicketCost } from '../../publicModelTierApi.js';",
    `import { getTicketCost } from ${JSON.stringify(tiersUrl)};`)));
const models = [
    ...Object.keys(assignments), 'test/tier100:online', 'test/tier100:free:online',
    'test/untiered-OPUS', 'test/untiered-image:online', 'test/untiered-thinking',
    'openai/o3-untiered', 'test/untiered-mini', 'test/untiered-default'
];
const cases = models.flatMap(model => [false, true].map(reasoning => {
    try {
        const budget = budgets.getModelBudget(model, reasoning);
        return { model, reasoning, micro_usd: Math.round(budget.spendingLimitUsd * 1_000_000) };
    } catch (error) {
        if (error.code !== 'unsupported_model_budget') throw error;
        return { model, reasoning, error: 'model_budget_unavailable' };
    }
}));
const digest = text => createHash('sha256').update(text).digest('hex');
const fixture = {
    web_sources: { [tierPath]: digest(tierSource), [budgetPath]: digest(budgetSource) },
    assignments,
    cases
};
const file = fileURLToPath(new URL('../internal/zkapi/testdata/web-model-budgets.json', import.meta.url));
const serialized = `${JSON.stringify(fixture, null, 2)}\n`;
if (mode === '--write') writeFileSync(file, serialized);
else if (readFileSync(file, 'utf8') !== serialized) throw new Error('Web model-budget behavior changed; review and regenerate the parity fixture.');
console.log(`Verified ${cases.length} model/reasoning cases against OA web policy.`);
