export function downloadUrl(source: 'github' | 'direct', format: 'dmg' | 'zip') {
  return `https://pet.miel.ing/latest?from=${source}&type=${format}`
}
