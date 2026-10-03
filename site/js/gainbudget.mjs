#!/usr/bin/env node
import {main} from "./cli.mjs";
process.exitCode=main(process.argv.slice(2),"gainbudget");
