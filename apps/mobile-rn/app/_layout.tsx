import { StatusBar } from "expo-status-bar";
import { useEffect } from "react";
import { checkOta } from "../src/ota";
import Tabs from "../src/Tabs";

export default function Root() {
  useEffect(() => {
    checkOta();
  }, []);
  return (
    <>
      <StatusBar style="auto" />
      <Tabs />
    </>
  );
}
