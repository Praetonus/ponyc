#include "control.h"
#include "../type/assemble.h"
#include "../type/subtype.h"
#include <assert.h>


bool show_partiality(pass_opt_t* opt, ast_t* ast)
{
  ast_t* child = ast_child(ast);
  bool found = false;

  // If we're a try exception, skip the body since errors raised there aren't
  // propagated.
  if((ast_id(ast) == TK_TRY) || (ast_id(ast) == TK_TRY_NO_CHECK))
    child = ast_sibling(child);

  while(child != NULL)
  {
    if(ast_canerror(child))
      found |= show_partiality(opt, child);

    child = ast_sibling(child);
  }

  if(found)
    return true;

  if(ast_canerror(ast))
  {
    ast_error_continue(opt->check.errors, ast, "an error can be raised here");
    return true;
  }

  return false;
}

bool verify_try(pass_opt_t* opt, ast_t* ast)
{
  assert((ast_id(ast) == TK_TRY) || (ast_id(ast) == TK_TRY_NO_CHECK));
  AST_GET_CHILDREN(ast, body, else_clause, then_clause);

  // It has to be possible for the left side to result in an error.
  if((ast_id(ast) != TK_TRY_NO_CHECK) && !ast_canerror(body))
  {
    ast_error(opt->check.errors, body,
      "try expression never results in an error");
    return false;
  }

  if(ast_canerror(then_clause))
  {
    ast_error(opt->check.errors, then_clause,
      "a try then clause cannot raise errors");

    show_partiality(opt, then_clause);
  }

  // Doesn't inherit error from the body.
  if(ast_canerror(else_clause))
    ast_seterror(ast);

  if(ast_cansend(body) || ast_cansend(else_clause) || ast_cansend(then_clause))
    ast_setsend(ast);

  if(ast_mightsend(body) || ast_mightsend(else_clause) ||
    ast_mightsend(then_clause))
    ast_setmightsend(ast);

  return true;
}


bool verify_partial_type(pass_opt_t* opt, ast_t* ast, ast_t* type)
{
  ast_t* method = opt->check.frame->method;
  ast_t* error = ast_childidx(method, 5);
  if(ast_id(error) == TK_NONE)
  {
    // The method isn't marked as partial. If this error isn't enclosed in a
    // try expression, this will be caught later in the pass.
    return true;
  }

  ast_t* current;
  ast_t* parent = ast;
  bool walk = true;
  bool exits_method = false;
  while(walk)
  {
    current = parent;
    parent = ast_parent(current);
    while((ast_id(parent) != TK_TRY) && (ast_id(parent) != TK_TRY_NO_CHECK) &&
      (parent != opt->check.frame->method))
    {
      current = parent;
      parent = ast_parent(current);
    }

    if((ast_id(parent) == TK_TRY) || (ast_id(parent) == TK_TRY_NO_CHECK))
    {
      if(current == ast_child(parent))
        walk = false;
    } else {
      exits_method = true;
      walk = false;
    }
  }

  ast_t* errtype;
  if(exits_method)
  {
    errtype = ast_child(error);
  } else {
    errtype = type_builtin(opt, ast, "Any");
    ast_setid(ast_childidx(errtype, 3), TK_VAL);
  }

  errorframe_t info = NULL;
  if(!is_subtype(type, errtype, &info, opt))
  {
    errorframe_t frame = NULL;
    if(exits_method)
    {
      ast_error_frame(&frame, ast, "this method cannot error with type %s",
        ast_print_type(type));
      ast_error_frame(&frame, errtype, "method error type is %s",
        ast_print_type(errtype));
    } else {
      ast_error_frame(&frame, ast, "error type must be a subtype of Any val");
      ast_free_unattached(errtype);
    }

    errorframe_append(&frame, &info);
    errorframe_report(&frame, opt->check.errors);
    return false;
  }

  if(!exits_method)
    ast_free_unattached(errtype);

  return true;
}


bool verify_error(pass_opt_t* opt, ast_t* ast)
{
  assert(ast_id(ast) == TK_ERROR);

  ast_seterror(ast);

  ast_t* value = ast_child(ast);
  ast_t* type = ast_type(value);

  return verify_partial_type(opt, ast, type);
}


bool verify_elseerror(pass_opt_t* opt, ast_t* ast)
{
  assert(ast_id(ast) == TK_ELSEERROR);

  ast_seterror(ast);

  ast_t* parent = ast_parent(ast);
  if(ast_id(parent) == TK_ELSEMATCH)
    parent = ast_parent(ast);

  ast_t* errors = (ast_t*)ast_data(parent);
  if(errors != NULL)
    return verify_partial_type(opt, ast, errors);

  return true;
}
