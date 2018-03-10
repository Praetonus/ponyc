#ifndef PACKAGE_H
#define PACKAGE_H

#include <platform.h>
#include "../libponyrt/ds/list.h"

#include <stdio.h>

#define SIGNATURE_LENGTH 64

PONY_EXTERN_C_BEGIN

typedef struct package_t package_t;
typedef struct package_group_t package_group_t;
typedef struct safe_package_t safe_package_t;
typedef struct magic_package_t magic_package_t;
typedef struct pass_opt_t pass_opt_t;
typedef struct ast_t ast_t;
typedef struct typecheck_t typecheck_t;

typedef enum safety_level_t
{
  SAFETY_SAFE,      // Package cannot perform any unsafe operation.
  SAFETY_RESULTS,   // Package can perform operations with undefined results.
  SAFETY_BEHAVIOUR, // Package can perform operations with undefined behaviour.
  SAFETY_FFI        // Package can perform FFI calls.
} safety_level_t;

DECLARE_LIST_SERIALISE(package_group_list, package_group_list_t,
  package_group_t)

// Function that will handle a path in some way.
typedef bool (*path_fn)(const char* path, pass_opt_t* opt, void* data);

/**
 * Cat together the 2 given path fragments into the given buffer.
 * The first path fragment may be absolute, relative or NULL
 */
void path_cat(const char* part1, const char* part2, char result[FILENAME_MAX]);

bool handle_path_list(const char* paths, path_fn f, pass_opt_t* opt,
  void* data);

/**
 * Initialises the search directories. This is composed of a "packages"
 * directory relative to the executable, plus a collection of directories
 * specified in the PONYPATH environment variable.
 */
bool package_init(pass_opt_t* opt);

/**
 * Appends a list of paths to the list of paths that will be searched for
 * packages.
 * Path list is semicolon (;) separated on Windows and colon (:) separated on
 * Linux and MacOS.
 */
void package_add_paths(const char* paths, pass_opt_t* opt);

/**
 * Appends a list of paths to the list of packages allowed to do unsafe
 * operations.
 * The list is semicolon (;) separated on Windows and colon (:) separated on
 * Linux and MacOS.
 * If this is never called, all packages are allowed to do unsafe operations.
 */
bool package_add_safe(const char* paths, pass_opt_t* opt,
  safety_level_t safety);

/**
 * Clear any safe packages that have been added.
 */
void package_clear_safe(pass_opt_t* opt);

/**
 * Add a magic package. When the package with the specified path is requested
 * the files will not be looked for and the source code given here will be used
 * instead. Each magic package can consist of only a single module.
 * The specified path is not expanded or normalised and must exactly match that
 * requested.
 */
void package_add_magic_src(const char* path, const char* src, pass_opt_t* opt);

/**
 * Add a magic package. Same as package_add_magic_src but uses an alternative
 * path instead.
 */
void package_add_magic_path(const char* path, const char* mapped_path,
  pass_opt_t* opt);

/**
 * Clear any magic packages that have been added.
 */
void package_clear_magic(pass_opt_t* opt);

/**
 * Load a program. The path specifies the package that represents the program.
 */
ast_t* program_load(const char* path, pass_opt_t* opt);

/**
 * Load a package. Used by program_load() and when handling 'use' statements.
 */
ast_t* package_load(ast_t* from, const char* path, pass_opt_t* opt);

/**
 * Free the package_t that is set as the ast_data of a package node.
 */
void package_free(package_t* package);

/**
 * Free the collection of safe packages.
 */
void package_safe_free(safe_package_t* safe_packages);

/**
 * Free the collection of magic packages.
 */
void package_magic_free(magic_package_t* magic_packages);

/**
 * Gets the package name, but not wrapped in an AST node.
 */
const char* package_name(ast_t* ast);

/**
 * Gets an AST ID node with a string set to the unique ID of the packaged. The
 * first package loaded will be $0, the second $1, etc.
 */
ast_t* package_id(ast_t* ast);

/**
 * Gets the package path.
 */
const char* package_path(ast_t* package);

/**
 * Gets the package qualified name.
 */
const char* package_qualified_name(ast_t* package);

/**
 * Gets the last component of the package path.
 */
const char* package_filename(ast_t* package);

/**
 * Gets the symbol wart for the package.
 */
const char* package_symbol(ast_t* package);

/**
 * Gets a string set to a hygienic ID. Hygienic IDs are handed out on a
 * per-package basis. The first one will be $0, the second $1, etc.
 * The returned string will be a string table entry and should not be freed.
 */
const char* package_hygienic_id(typecheck_t* t);

/**
 * Returns true if the current package can perform unsafe operations of safety
 * level `safety`.
 */
bool package_allow_unsafe(typecheck_t* t, safety_level_t safety);

/**
 * Gets the alias of a package in the current module from the hygienic ID
 * of that package. Returns NULL if there is no alias. The package must have
 * been imported in the current module.
 *
 * For example, if the package `foo` was imported in the current module with
 * `use foo = "foo"` and the global ID of the package "foo" is `$2`, the call
 * `package_alias_from_id(current_module_ast, "$2")` will return the string
 * "foo".
 */
const char* package_alias_from_id(ast_t* module, const char* id);

/**
 * Adds a package to the dependency list of another package.
 */
void package_add_dependency(ast_t* package, ast_t* dep);

const char* package_signature(ast_t* package);

size_t package_group_index(ast_t* package);

package_group_t* package_group_new();

void package_group_free(package_group_t* group);

/**
 * Build a list of the dependency groups (the strongly connected components) in
 * the package dependency graph. The list is topologically sorted.
 */
package_group_list_t* package_dependency_groups(ast_t* first_package);

const char* package_group_signature(package_group_t* group);

void package_group_dump(package_group_t* group);

/**
 * Cleans up the list of search directories.
 */
void package_done(pass_opt_t* opt);

pony_type_t* package_dep_signature_pony_type();

pony_type_t* package_signature_pony_type();

pony_type_t* package_group_dep_signature_pony_type();

pony_type_t* package_group_signature_pony_type();

pony_type_t* package_pony_type();

pony_type_t* package_group_pony_type();

bool is_path_absolute(const char* path);

bool is_path_relative(const char* path);

PONY_EXTERN_C_END

#endif
