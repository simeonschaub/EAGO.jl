push!(LOAD_PATH,"../src/")

using Documenter, DocumenterTools
using EAGO, IntervalArithmetic, MathOptInterface, McCormick, JuMP

import McCormick: final_cut, mid3v, precond_and_contract!, AbstractMCCallback, populate_affine!,
                  dline_seg, correct_exp!, cut, mid_grad, preconditioner_storage, newton, secant,
                  MCCallback, contract!, affine_exp!

import EAGO: ExtensionType, Evaluator, variable_dbbt!, set_current_node!,
             VariableInfo, Log, aggressive_filtering!,
             bool_indx_diff, trivial_filtering!, SIPResult, SIPProblem, 
             GlobalOptimizer, InputProblem, ParsedProblem, is_integer_feasible_relaxed, 
             local_problem_status, default_upper_heuristic, label_branch_variables!,
             label_fixed_variables!, AbstractDirectedGraph, AbstractCache, 
             AbstractCacheAttribute, initialize!, f_init!, r_init!, fprop!, rprop!,
             Variable, Subexpression, Expression, Constant, Parameter
             
import EAGO.Script: dag_flattening!, register_substitution!, Template_Graph,
                    Template_Node, scrub, scrub!, flatten_expression!

const MOI = MathOptInterface

@info "Making documentation..."
makedocs(modules = [EAGO, McCormick],
         doctest = false,
         format = Documenter.HTML(
                prettyurls = get(ENV, "CI", nothing) == "true",
                canonical = "https://PSORLab.github.io/EAGO.jl/stable/",
                collapselevel = 1,
         ),
         authors = "Matthew E. Wilhelm",
         #repo = "https://github.com/PSORLab/EAGO.jl/blob/{commit}{path}#L{line}",
         sitename = "EAGO.jl: Easy Advanced Global Optimization",
         pages = Any["Introduction" => "index.md",
                     "Quick Start" => Any["Quick_Start/qs_landing.md",
                                          "Quick_Start/guidelines.md",
                                          "Quick_Start/starting.md",
                                          "Quick_Start/medium.md",
                                          "Quick_Start/custom.md"
                                          ],
                     "McCormick Operator Library" => Any["McCormick/overview.md",
                                                         "McCormick/usage.md",
                                                         "McCormick/operators.md",
                                                         "McCormick/type.md",
                                                         "McCormick/implicit.md"
                                                        ],
                     "Global Optimizer" => Any["Optimizer/optimizer.md",
                                               "Optimizer/bnb_back.md",
                                               "Optimizer/relax_back.md",
                                               "Optimizer/domain_reduction.md",
                                               "Optimizer/high_performance.md",
                                               "Optimizer/udf_utilities.md"
                                               ],
                     "Semi-Infinite Programming" => "SemiInfinite/semiinfinite.md",
                     "Contributing to EAGO"      => Any["Dev/contributing.md",
                                                        "Dev/future.md"
                                                        ],
                     "References"  => "ref.md",
                     "Citing EAGO" => "cite.md"]
)

@info "Deploying documentation..."
deploydocs(repo = "github.com/PSORLab/EAGO.jl.git",
           push_preview  = true)
