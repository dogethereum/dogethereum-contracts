import {auctionBot} from "./main";

auctionBot()
  .then(() => {
    console.log("Finished");
    process.exit(0);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });