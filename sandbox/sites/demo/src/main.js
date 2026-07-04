// Entrée JS servie par Vite (HMR). Modifier ce fichier -> mise à jour live.
const el = document.getElementById('vite-app')
if (el) {
  el.textContent = '⚡ Vite HMR actif — édite src/main.js pour voir le hot-reload !'
  el.style.color = '#7c3aed'
}
console.log('[vite] main.js chargé via', import.meta.url)
