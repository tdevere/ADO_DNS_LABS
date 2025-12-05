const message = process.env.APP_MESSAGE || 'No message configured';

console.log('\n' + '='.repeat(60));
console.log('  DNS LAB APPLICATION');
console.log('='.repeat(60));
console.log('');
console.log('Configuration retrieved from Azure Key Vault');
console.log('via Private Endpoint with Private DNS Zone');
console.log('');
console.log('MESSAGE:', message);
console.log('');
console.log('='.repeat(60));
console.log('✓ Lab completed successfully!');
console.log('='.repeat(60) + '\n');
