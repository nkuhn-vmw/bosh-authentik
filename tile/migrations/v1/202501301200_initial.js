/*
 * Initial Migration for Authentik Tile
 *
 * This migration handles the initial installation and serves as a
 * template for future migrations.
 *
 * Migrations are JavaScript files that export a 'migrate' function.
 * The function receives the current product configuration and returns
 * the migrated configuration.
 */

exports.migrate = function(input) {
  // Initial migration - no changes needed for fresh installs
  // Future migrations can transform the input as needed

  // Example transformation (commented out):
  // if (input.product_properties) {
  //   // Rename a property
  //   if (input.product_properties['.properties.old_name']) {
  //     input.product_properties['.properties.new_name'] =
  //       input.product_properties['.properties.old_name'];
  //     delete input.product_properties['.properties.old_name'];
  //   }
  // }

  return input;
};
