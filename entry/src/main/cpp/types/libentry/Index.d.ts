export interface SshStatus {
  nativeAvailable: boolean;
  state: string;
  message: string;
  fingerprint: string;
  connectionId: number;
}
export interface TransferStatus {
  state: string;
  message: string;
  bytes: number;
  total: number;
}
export const connect: (host: string, port: number) => boolean;
export const authenticate: (user: string, password: string, fingerprint: string) => boolean;
export const disconnect: () => void;
export const status: () => SshStatus;
/** Duplicates fd before returning. The caller retains ownership of the original. */
export const startTransfer: (upload: boolean, fd: number, remotePath: string, connectionId: number) => boolean;
export const cancelTransfer: () => void;
export const transferStatus: () => TransferStatus;

export interface RemoteEntry {
  name: string;
  kind: string;
  size: number;
  modified: number;
}
export interface RemoteStatus {
  state: string;
  message: string;
  path: string;
  entries: RemoteEntry[];
}
export const startRemote: (action: string, path: string, newName: string, connectionId: number) => boolean;
export const remoteStatus: () => RemoteStatus;
