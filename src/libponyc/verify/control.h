#ifndef VERIFY_CONTROL_H
#define VERIFY_CONTROL_H

#include <platform.h>
#include "../ast/ast.h"
#include "../pass/pass.h"

PONY_EXTERN_C_BEGIN

bool show_partiality(pass_opt_t* opt, ast_t* ast);

bool verify_try(pass_opt_t* opt, ast_t* ast);

bool verify_partial_type(pass_opt_t* opt, ast_t* ast, ast_t* type);

bool verify_error(pass_opt_t* opt, ast_t* ast);

bool verify_elseerror(pass_opt_t* opt, ast_t* ast);

PONY_EXTERN_C_END

#endif
