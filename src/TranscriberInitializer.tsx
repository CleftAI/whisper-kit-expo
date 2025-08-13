
import { useEffect, ReactNode } from 'react';
import { loadTranscriber } from '.';

interface TranscriberInitializerProps {
  children: ReactNode;
}

export const TranscriberInitializer = ({ children }: TranscriberInitializerProps) => {
  useEffect(() => {
    console.log("Running the initialization effect for the transcriber");
    loadTranscriber().then((res) => console.log(res ? "success" : "failure"));
  }, []);

  return <>{children}</>;
}