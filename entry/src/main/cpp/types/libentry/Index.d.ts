export interface SshStatus {
  nativeAvailable: boolean;
  state: string;
  message: string;
  fingerprint: string;
}
export const connect: (host: string, port: number) => boolean;
export const authenticate: (user: string, password: string, fingerprint: string) => boolean;
export const disconnect: () => void;
export const status: () => SshStatus;
