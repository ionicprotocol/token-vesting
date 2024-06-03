import { parse } from "csv-parse/sync";
import hre from "hardhat";
import fs from "fs";
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
  const file = fs.readFileSync(`airdrop-amounts-final.csv`);
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
  console.log("num batches: ", batches.length);
  console.log("sum: ", formatEther(sum));
  console.log("sum raw: ", sum);
  const tokenVesting = await hre.viem.getContractAt(
    "TokenVesting",
    TOKEN_VESTING_MODE
  );
  for (const batch of batches) {
    // const vests = await Promise.all(
    //   batch.map(async (row) => {
    //     const vest = (await tokenVesting.read.vests([row.user])) as [bigint];
    //     return { ...row, vestAmount: vest[0] };
    //   })
    // );
    // const _batch = vests.filter((row) => row.vestAmount === 0n);
    const _batch = batch;
    const tx = await tokenVesting.write.setVestingAmounts([
      _batch.reduce((sum, row) => (sum += BigInt(row.vested_amount)), 0n),
      _batch.map((row) => row.user),
      _batch.map((row) => BigInt(row.vested_amount)),
    ]);
    const receipt = await client.waitForTransactionReceipt({ hash: tx });
    console.log("receipt.transactionHash: ", receipt.transactionHash);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });