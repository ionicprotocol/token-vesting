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

const TOKEN_VESTING_MODE = "";

async function main() {
  const file = fs.readFileSync(`airdrop-amounts-final.csv`);
  const csv = parse(file, {
    columns: true,
    skip_empty_lines: true,
  }) as Row[];

  // console.log("csv: ", csv);
  const batch: Row[] = [];
  const batches: Row[][] = [];
  let sum = 0n;
  csv.forEach((row) => {
    sum += BigInt(row.vested_amount);
    batch.push(row);
    if (batch.length === BATCH_SIZE) {
      batches.push(batch);
      batch.length = 0;
    }
  });
  console.log("num batches: ", batches.length);
  console.log("sum: ", formatEther(sum));
  const tokenVesting = await hre.viem.getContractAt(
    "TokenVesting",
    TOKEN_VESTING_MODE
  );
  for (const batch of batches) {
    await tokenVesting.write.setVestingAmounts([
      batch.map((row) => row.user),
      batch.map((row) => BigInt(row.vested_amount)),
    ]);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });