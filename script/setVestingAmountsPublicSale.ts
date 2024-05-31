import { parse } from "csv-parse/sync";
import hre from "hardhat";
import fs from "fs";
import { Address, formatEther, parseEther, parseEventLogs } from "viem";

const BATCH_SIZE = 1000;

type Row = {
  TxHash: string;
  BlockNumber: string;
  UnixTimestamp: string;
  FromAddress: string;
  ToAddress: string;
  ContractAddress: string;
  Type: string;
  Value: string;
  Fee: string;
  Status: string;
  ErrCode: string;
  CurrentPrice: string;
  TxDateOpeningPrice: string;
  TxDateClosingPrice: string;
};

const TOKEN_VESTING_MODE = "0xDA061A5D6fc9F3D40f6505ce38AEb8793A29eDE8";
// const VESTED_AMOUNT_PER_ADDRESS = parseEther("26666.4");
const VESTED_AMOUNT_PER_ADDRESS = 0n;

async function main() {
  const client = await hre.viem.getPublicClient();
  const file = fs.readFileSync(`s1-ionic-buys.csv`);
  const csv = parse(file, {
    columns: true,
    skip_empty_lines: true,
  }) as Row[];

  const tokenVesting = await hre.viem.getContractAt(
    "PublicSaleTokenVesting",
    TOKEN_VESTING_MODE
  );
  const tx = await tokenVesting.write.setVestingAmounts([
    csv.reduce((sum) => (sum += VESTED_AMOUNT_PER_ADDRESS), 0n),
    csv.map((row) => row.FromAddress),
    csv.map(() => VESTED_AMOUNT_PER_ADDRESS),
  ]);
  const receipt = await client.waitForTransactionReceipt({ hash: tx });
  console.log("receipt.transactionHash: ", receipt.transactionHash);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
