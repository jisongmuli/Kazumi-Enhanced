// Keep the child alive only while the Kazumi parent owns its stdin pipe.
process.stdin.resume();
process.stdin.on('end', () => process.exit(0));
await import('./danmu_api/server.js');
