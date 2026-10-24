import metadata from './generated/release.json';

type DiskImage = {
  url: string;
  size: number;
  sha256: string;
  githubUrl: string;
  checksumUrl: string;
};

// Keep the optional format typed even when generated metadata contains null.
const release: Omit<typeof metadata, 'dmg'> & { dmg: DiskImage | null } = metadata;
export default release;
