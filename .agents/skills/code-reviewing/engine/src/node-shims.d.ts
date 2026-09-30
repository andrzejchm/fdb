declare module 'node:fs' {
  export function existsSync(path: string): boolean;
  export function mkdirSync(path: string, options?: { recursive?: boolean }): void;
  export function readFileSync(path: string | number, encoding: string): string;
  export function readdirSync(path: string): string[];
  export function rmSync(path: string, options?: { force?: boolean; recursive?: boolean }): void;
  export function writeFileSync(path: string, data: string): void;
}

declare module 'node:path' {
  export function basename(path: string): string;
  export function dirname(path: string): string;
  export function join(...parts: string[]): string;
  export function relative(from: string, to: string): string;
}

declare module 'node:url' {
  export function fileURLToPath(url: string | URL): string;
}

declare module 'node:child_process' {
  export function execSync(command: string, options: { encoding: string }): string;
  export function spawnSync(
    command: string,
    args: string[],
    options: { encoding: string },
  ): { status: number | null; stdout: string; stderr: string };
}

declare module 'node:crypto' {
  export function createHash(algorithm: string): {
    update(data: string): { digest(encoding: 'hex'): string };
  };
}

declare const process: {
  argv: string[];
  stdin: {
    isTTY?: boolean;
    setEncoding(encoding: string): void;
    on(event: 'data', handler: (chunk: string) => void): void;
    on(event: 'end', handler: () => void): void;
    on(event: 'error', handler: (error: unknown) => void): void;
    resume(): void;
  };
  stdout: { write(chunk: string): void };
  cwd(): string;
  chdir(path: string): void;
  exit(code?: number): never;
};
