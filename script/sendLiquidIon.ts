import { parse } from "csv-parse/sync";
import hre from "hardhat";
import { readFileSync, writeFileSync } from "fs";
import { Address } from "viem";

type Row = {
  user: Address;
  total_amount: string;
  liquid_amount: string;
  vested_amount: string;
};

const ION_MODE = "0x18470019bf0e94611f15852f7e93cf5d65bc34ca";
const deployer = "0x1155b614971f16758C92c4890eD338C9e3ede6b7";

async function main() {
  const client = await hre.viem.getPublicClient();
  const file = readFileSync(`deduped.csv`);
  const csv = parse(file, {
    columns: true,
    skip_empty_lines: true,
  }) as Row[];

  console.log(`Sending liquid ION to ${csv.length} users`);
  const ionToken = await hre.viem.getContractAt("IERC20", ION_MODE);
  const balance = await ionToken.read.balanceOf([deployer]);
  console.log(`Deployer balance: ${balance}`);
  const totalIonRequired = csv.reduce(
    (sum, row) => (sum += BigInt(row.liquid_amount)),
    0n
  );
  console.log(`Total ION required: ${totalIonRequired}`);
  if (totalIonRequired > balance) {
    throw new Error("Insufficient ION balance");
  }
  let i = 1;
  const successful: (Row & { tx: string })[] = [];
  const failure = [];
  for (const row of csv) {
    console.log(
      `Sending liquid ION: ${row.liquid_amount} to ${row.user} (${i}/${csv.length})`
    );
    try {
      const tx = await ionToken.write.transfer([
        row.user,
        BigInt(row.liquid_amount),
      ]);
      const receipt = await client.waitForTransactionReceipt({ hash: tx });
      console.log("Transaction receipt received: ", receipt);
      successful.push({ ...row, tx });
    } catch (e) {
      console.log("error: ", e);
      failure.push({ ...row, error: (e as Error).message });
    }
    i++;
  }
  const content =
    "user,total_amount,liquid_amount,vested_amount,tx\n" +
    successful
      .map((row) => {
        return `${row.user},${row.total_amount},${row.liquid_amount},${row.vested_amount},${row.tx}`;
      })
      .join("\n");
  writeFileSync("success.csv", content);

  const failureContent =
    "user,total_amount,liquid_amount,vested_amount,error\n" +
    failure
      .map((row) => {
        return `${row.user},${row.total_amount},${row.liquid_amount},${row.vested_amount},${row.error}`;
      })
      .join("\n");
  writeFileSync("failure.csv", failureContent);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
