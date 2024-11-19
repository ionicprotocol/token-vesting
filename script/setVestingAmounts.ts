import hre from "hardhat";
import * as dotenv from "dotenv";
dotenv.config();
import { createPublicClient, http } from 'viem';
import { mode } from 'viem/chains';
import { createClient } from "@supabase/supabase-js";
import { parse } from "csv-parse/sync";
import fs from "fs";
import { Address, formatEther, parseEther } from "viem";
const BATCH_SIZE = 1000;
// Supabase configuration
const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY!;
const TABLE_NAME = "airdrop_season_2";
type Row = {
  claimed: any;
  user: Address;
  ion_amount: string;
  initial_ion_sent: string | null;
  remaining_ion: string | null;
  distributed: boolean;
  vesting_set: boolean;
};
const TOKEN_VESTING_MODE = "0x3931803bE318676C8F32A40F97448b4B26bf20a1";
async function main() {
  console.log("Connecting to Supabase:", SUPABASE_URL);
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  let totalAmount = 0n;
  let totalLiquid = 0n;
  let totalVested = 0n;
  let from = 0;
  const PAGE_SIZE = 10000;
  while (true) {
    console.log(`\nFetching records ${from} to ${from + PAGE_SIZE}...`);
    const { data: rows, error, count } = await supabase
      .from(TABLE_NAME)
      .select('*', { count: 'exact' })
      .eq('claimed', true)
      .range(from, from + PAGE_SIZE - 1)
      .throwOnError();
    if (error) {
      console.error("Error fetching data:", error);
      process.exit(1);
    }
    if (!rows || rows.length === 0) {
      break;
    }
    console.log(`Processing ${rows.length} records...`);
    
    // Initialize batch totals
    let batchAmount = 0n;
    let batchLiquid = 0n;
    let batchVested = 0n;
    rows.forEach((row: Row) => {
      if (row.claimed === true) {
        // console.log('Row values:', {
        //   ion_amount: row.ion_amount,
        //   initial_ion_sent: row.initial_ion_sent,
        //   remaining_ion: row.remaining_ion,
        //   typeof_ion_amount: typeof row.ion_amount
        // });

        try {
          // Use parseEther for precise decimal handling
          const amountWei = parseEther(row.ion_amount.toString());
          batchAmount += amountWei;
          totalAmount += amountWei;

          const liquidAmountWei = parseEther((row.initial_ion_sent || "0").toString());
          batchLiquid += liquidAmountWei;
          totalLiquid += liquidAmountWei;

          const vestedAmountWei = parseEther((row.remaining_ion || "0").toString()); 
          batchVested += vestedAmountWei;
          totalVested += vestedAmountWei;
        } catch (error) {
          console.error('Error processing row:', error);
          console.error('Problematic row:', row);
        }
      }
    });
    console.log("Batch Summary:");
    console.log("Batch Amount (ION):", formatEther(batchAmount));
    console.log("Batch Liquid (ION):", formatEther(batchLiquid));
    console.log("Batch Vested (ION):", formatEther(batchVested));
    from += PAGE_SIZE;
    if (count && from >= count) {
      break;
    }
  }
  console.log("\nFinal Summary:");
  console.log("Total Amount (ION):", formatEther(totalAmount));
  console.log("Total Liquid Amount (ION):", formatEther(totalLiquid));
  console.log("Total Vested Amount (ION):", formatEther(totalVested));
  console.log("\nRaw Values (in wei):");
  console.log("Total Amount:", totalAmount.toString());
  console.log("Total Liquid Amount:", totalLiquid.toString());
  console.log("Total Vested Amount:", totalVested.toString());

  // Organize rows into batches
  const batches: Row[][] = [];
  let currentBatch: Row[] = [];
  
  const { data: allRows, error: fetchError } = await supabase
    .from(TABLE_NAME)
    .select('*')
    .eq('claimed', true)
    .eq('distributed', true)
    .eq('vesting_set', false)
    .throwOnError();

  if (fetchError) {
    console.error("Error fetching data:", fetchError);
    process.exit(1);
  }

  console.log(`Found ${allRows?.length || 0} records that need vesting set up`);

  // Create batches
  allRows?.forEach((row: Row) => {
    currentBatch.push(row);
    if (currentBatch.length === BATCH_SIZE) {
      batches.push(currentBatch);
      currentBatch = [];
    }
  });
  
  // Push the last batch if it's not empty
  if (currentBatch.length > 0) {
    batches.push(currentBatch);
  }

  const tokenVesting = await hre.viem.getContractAt(
    "TokenVesting",
    TOKEN_VESTING_MODE
  );

  let i = 1;
  for (const batch of batches) {
    console.log(`Processing batch ${i} of ${batches.length}`);
    try {
      const vests = await Promise.all(
        batch.map(async (row) => {
          const vest = (await tokenVesting.read.vests([row.user])) as [bigint];
          const vestedAmountWei = parseEther((parseFloat(row.ion_amount) * 0.84).toString());
          return { 
            ...row, 
            vestAmount: vest[0],
            vestedAmountWei
          };
        })
      );

      const _batch = vests.filter((row) => row.vestAmount === 0n);
      if (_batch.length > 0) {
        const tx = await tokenVesting.write.setVestingAmounts([
          _batch.reduce((sum, row) => sum + row.vestedAmountWei, 0n), // Use calculated vested amount
          _batch.map((row) => row.user),
          _batch.map((row) => row.vestedAmountWei), // Use calculated vested amount
        ]);
        const receipt = await (await hre.viem.getPublicClient()).waitForTransactionReceipt({ hash: tx });
        console.log("Transaction hash: ", receipt.transactionHash);

        // Update Supabase for successful vesting setup
        const updates = _batch.map((row) => ({
            user: row.user,
            vesting_set: true
        }));

        const { error } = await supabase
          .from(TABLE_NAME)
          .upsert(updates, { onConflict: 'user' });

        if (error) {
          console.error("Error updating Supabase:", error);
        } else {
          console.log(`Updated ${updates.length} records in Supabase`);
        }
      } else {
        console.log("No new vesting amounts to set for batch");
      }
    } catch (error) {
      console.error(`Error processing batch ${i}:`, error);
      console.log("Continuing with next batch...");
    }
    console.log("batch: ", i);
    i++;
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
