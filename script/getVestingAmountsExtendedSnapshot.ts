import { parse } from "csv-parse/sync";
import hre from "hardhat";
import { readFileSync, writeFileSync } from "fs";
import { Address, formatEther } from "viem";

const BATCH_SIZE = 1000;

type Row = {
  user: Address;
  total_amount: string;
  liquid_amount: string;
  vested_amount: string;
};

const TOKEN_VESTING_MODE = "0xa7BC89F9Bcd2E6565c250182767f20e2aC89bc7B";

async function main() {
  const client = await hre.viem.getPublicClient();
  const file = readFileSync(`airdrop-amounts-final-extended.csv`);
  const csv = parse(file, {
    columns: true,
    skip_empty_lines: true,
  }) as Row[];

  // console.log("csv: ", csv);
  let batch: Row[] = [];
  const batches: Row[][] = [];
  let sum = 0n;
  csv.forEach((row) => {
    sum += BigInt(row.vested_amount);
    batch.push(row);
    if (batch.length === BATCH_SIZE) {
      batches.push(batch);
      batch = [];
    }
  });
  if (batch.length > 0) {
    batches.push(batch);
  }
  console.log("num batches: ", batches.length);
  const tokenVesting = await hre.viem.getContractAt(
    "TokenVesting",
    TOKEN_VESTING_MODE
  );
  let i = 1;
  const headerRow = "user,total_amount,liquid_amount,vested_amount\n";
  const deduped: Row[] = [];
  for (const batch of batches) {
    const vests = await Promise.all(
      batch.map(async (row) => {
        const vest = (await tokenVesting.read.vests([row.user])) as [
          bigint,
          bigint,
          boolean
        ];
        return { ...row, vestAmount: vest[0] };
      })
    );
    const _batch = vests.filter((row) => row.vestAmount === 0n);
    console.log(
      `Processing batch ${i} of ${batches.length} batches: Batch Length - ${_batch.length}`
    );
    // const _batch = batch;
    if (_batch.length > 0) {
      deduped.push(..._batch);
    } else {
      console.log("No new vesting amounts to set for batch");
    }
    i++;
  }
  console.log(`Total deduped: ${deduped.length} rows`);
  const sumLiquid = deduped.reduce(
    (sum, row) => (sum += BigInt(row.liquid_amount)),
    0n
  );
  console.log("sumLiquid: ", formatEther(sumLiquid));

  const sumVested = deduped.reduce(
    (sum, row) => (sum += BigInt(row.vested_amount)),
    0n
  );
  console.log("sumVested: ", formatEther(sumVested));

  const content =
    headerRow +
    deduped
      .map((row) => {
        return `${row.user},${row.total_amount},${row.liquid_amount},${row.vested_amount}`;
      })
      .join("\n");
  writeFileSync("deduped.csv", content);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
