#!ruby
#
# Written by Zoran Lazarevic
# http://www.cs.columbia.edu/~laza/
# This is free software
#

#
#
# MYCIN Expert System
#
# This is a Ruby rewrite of the Lisp code given in the book:
#   Peter Norvig:  "Paradigms of Artificial Intelligence Programming. 
#                   Case Studies in Common Lisp"
#   Morgan Kaufmann Publishers, San Francisco. 1992
#   ISBN 1-55860-191-0
#
#   Excerpts from the book:
#     " MYCIN lead to the development of the EMYCIN expert-system shell...
#       EMYCIN is a backward-chaining rule interpreter that has much in common
#       with Prolog. However, there are four important differences. First,
#       and most importantly, EMYCIN deals with uncertainty. Instead of 
#       insisting that all predications be true or false, EMYCIN associates
#       *certainty factor* with each predication. Second, EMYCIN caches the
#       results of its computation so that they not be duplicated. Third,
#       EMYCIN provides an easy way for the system to ask the user for 
#       information. Fourth, it provides explanations of its behavior. This
#       can be summed up in the equation:
#       
#           EMYCIN = Prolog + uncertainty + caching + questions + explanations
#     "  
#     "The MYCIN expert system was one of the earliest and remain one of the 
#      best known. It was written by Dr. Edward Shortliffe in 1974 as an 
#      experiment in medical diagnosis. 
#
#
# A typical rule:
#
#            param  context   operation value
#            -----  -------   --------- -----
#
#   (defrule 52                                         <--- rule number
#       if  (site   culture         is  blood )
#           (gram   organism        is  neg   )         <--- premise/condition
#           (morphl organism        is  rod   )
#           (burn   patient         is  serious)
#       then 0.4                                        <--- confidence factor (cf)
#           (identity   organism    is  pseudomonas )   <--- conclusion
#   )
#
#

module Enumerable
    # Check if every element returns true
    def every
        each do |value|
            result = yield(value)
            return false unless result
        end
        return true
    end
    
    # Check if at least one element returns true
    def some
        each do |value|
            result = yield(value)
            return true if result
        end
        return false
    end
    
    # Return two arrays, one with elements that satisfy the test,
    # and another that fail the test
    def partition_if
        pass, fail = [], []
        each do |value|
            result = yield(value)
            if result then pass.push(value)
            else           fail.push(value)
            end
        end
        return pass, fail
    end
    
end


def println(str = "")
    print str + "\n"
end

def pdbg(str = "")
    print str + "\n"
end




#
# Certainty Factors
#

True    = +1.0
Unknown =  0.0
False   = -1.0

Certainty_Cutoff = 0.2

Ask_First = true
Call_find_out = true



# 
# Combines two probabilites. Combining +1.0 and -1.0 is an error
# 
def cf_or ( a, b )
# Combine for 'A or B'
    if a>0 and b>0
        a + b - a*b
    elsif a<0 and b<0
        a + b + a*b
    else
        (a + b) / ( 1 - [a.abs, b.abs].min )
    end
end

def cf_and( a, b )
# Combine certainties for 'A and B'
    [a,b].min
end

def cf_true? cf
    cf > Certainty_Cutoff
end

def cf_false? cf
    cf < ( Certainty_Cutoff - 1.0 )
end

def is_cf? cf
    cf.kind_of? Float  and  False <= cf  and  cf <= True
end




#
# In original Mycin, there were three types of contexts:
#    patients, cultures, and organisms
#
class Context
public
    attr_accessor   :name, :number, :initial_data, :goals
    def initialize(name, initial_data=[],  goals=[])
        @name = name; @number=0
        @initial_data=initial_data; @goals=goals
    end
    
    def new_instance
    # Create a new instance of this context, write a message, 
    # and store the instance in two places in the dB:
    #   - under key "current-instance"
    #   - under the name of the context
        @number+=1
        return @name + "-" + @number.to_s
    end
    
    def to_s
        "#{@name}-#{@number} 
        init=[ #{@initial_data.join(', ')} ]
        goals=[ #{@goals.join(', ')} ]
        "
    end
end
    


class ReplyVerification
public
    attr_accessor :verifyproc, :args, :help
    def initialize( verifyproc=proc{|x,args|true}, 
                    helpproc=proc{|args| "Any input is valid"}, 
                    args=nil )
        raise(ArgumentError, "Verify function is not a Proc #{verifyproc}")   unless verifyproc.kind_of? Proc 
        raise(ArgumentError, "Help function is not a Proc #{helpproc}") unless helpproc.kind_of? Proc 
        @verifyproc = verifyproc
        @help   = helpproc
        @args   = args
    end
    
    def verify(x)
        @verifyproc.call(x,@args)
    end
    def help
        @help.call(@args)
    end
end


class MemberVerification < ReplyVerification
    def initialize( list )
        raise(ArgumentError, "Member list must be an array #{list}")   unless list.kind_of? Array
        raise(ArgumentError, "All members must be Strings") unless list.every{|x| x.kind_of? String }
        
        super(  proc{|x,list| list.member?(x)}, 
                proc{|list| "Must be one of: #{list.join(', ')}"},
                list
            )
    end
end

class EMycin
public

    def initialize
        @operations = Operations.new    # All valid operations. E.g. "is" in premise "site culture is blood"      
        @parameters = Parameters.new    # All valid parameters, e.g. name, sex, age
        @rules      = Rules.new         # List of rules in the database
        @db         = MycinDb.new       # Database of reasoning results, changes through inference
        @asked      = []                # Tracks which questions have been already asked
        @known      = Hash.new          # Tracks known answers to the questions 
        @current_instance = nil         # Multiple questions are asked for one instance, e.g. "patient-1", or "organism-2"
        @current_rule = nil             # Printed when user asks why is the question being asked
        @instances  = Hash.new          # Used for looking up context->instance, e.g. "patient"->"patient-1"
    end

    def clear
        @operations .clear           
        @parameters .clear
        @rules      .clear
        @db         .clear
        @asked      = []
        @known      .clear
        @current_instance = nil
        @current_rule = nil
        @instances = []
    end

    class ValueCf
    public
        attr_accessor :value, :cf
        def initialize( value, cf )
            raise(ArgumentError, "Invalid certainty factor #{cf}") unless is_cf? cf 
            @value  = value
            @cf     = cf
        end
        def to_s
            @value.to_s + " " + @cf.to_s
        end
        
    end








    class Parameter
    public
        attr_accessor :name, :context, :type_restriction, :prompt ,
                      :ask_first, :reader
        def initialize( 
                    name,
                    context=nil,
                    type_restriction=ReplyVerification.new,     # call this to check if user's entry valid
                    prompt="What is the %s of %s?",
                    ask_first=false,
                    reader=IO.method("readline") )
            raise(ArgumentError, "Verify function is not a ReplyVerification")   unless type_restriction.kind_of? ReplyVerification
            
            @name = name;               @context = context; 
            @prompt = prompt;           @type_restriction=type_restriction;
            @ask_first = ask_first;     @reader = reader
        end
    end

    
    class Parameters < Hash
        def get( name ) 
        # Lookup the parameter structure with this name
        # Create new parameter if not already defined.
            self[name]  or  self[name]=Parameter.new(name)
        end
        
        def put( param )
            self[param.name]=param
        end
        
        def type(name)
            get(name).type_restriction
        end
        def defined?( name ) 
            self[name]
        end
    end
    
    
    
    def add_parameter(
                    name,
                    context=nil,
                    type_restriction=ReplyVerification.new,     # call this to check if user's entry valid
                    prompt="What is the %s of %s?",
                    ask_first=false,
                    reader=IO.method("readline") )
    
        @parameters.put( Parameter.new( name, context, type_restriction, prompt, ask_first, reader ) )
    end
    
    
    def new_instance(context)
    # Create a new instance of this context, write a message, 
    # and store the instance in two places in the dB:
    #   - under key "current-instance"
    #   - under the name of the context
        instance = context.new_instance
        println "------- #{instance} -------"
        @current_instance  = instance
        put_instance context.name, instance
        return instance
    end



    class Operations < Hash
    public
        def put( op_name, op_proc )
        # key=operation name string
        # value = proc{|a,b|} object
            raise(ArgumentError, "Operation #{op_name} does not have a valid Proc (#{op_proc})")  \
                unless (op_proc.kind_of? Proc) and (op_proc.arity == 2)
            self[op_name] = op_proc
        end
        
        def get( op_name )
            self[op_name]
        end
        
    end
    
    
    def add_operation( op_name, op_proc )
        @operations.put op_name, op_proc 
    end
    
    
    class Premise
    #
    # A typical premise is:
    #   "site  culture  is  blood"
    # i.e  [parameter, context, operation, value] 
    # 
    public
        attr_accessor   :param, :inst, :op_name, :op, :val
        def initialize(param, inst, op_name, op_proc, val, registered_parameters)
            p = registered_parameters.get(param)
            raise(ArgumentError, "Invalid Parameter #{param}") unless p 
            raise(ArgumentError, "Invalid Parameter #{param} for #{inst}") unless p.context == inst 
            raise(ArgumentError, "Invalid value #{val}") unless p.type_restriction.verify(val) 
#            raise(ArgumentError, "Invalid Instance  #{inst}")  unless Parameter.defined?(param) 
            @param      = param
            @inst       = inst
            @op_name    = op_name
            @op         = op_proc
            @val        = val
        end
        
        def Premise.new_from_string(str, registered_operations, registered_parameters )
            param, inst, op_name, val = str.split
            op_proc = registered_operations.get(op_name)
            raise(ArgumentError, "Invalid operation '#{op_name}' in premise '#{str}'") if op_proc.nil?
            Premise.new( param, inst, op_name, op_proc, val, registered_parameters )
        end
        
        def to_s
            "The #{@param} of the #{@inst} #{@op_name} #{@val}"
        end
    end
    
    class Conclusion < Premise
    end
    
    class Rule
    # A typical rule:
    #
    #            param  context   operation value
    #            -----  -------   --------- -----
    #
    #   (defrule 52                                         <--- rule number
    #       if  (site   culture         is  blood )
    #           (gram   organism        is  neg   )         <--- premise/condition
    #           (morphl organism        is  rod   )
    #           (burn   patient         is  serious)
    #       then 0.4                                        <--- confidence factor (cf)
    #           (identity   organism    is  pseudomonas )   <--- conclusion
    #   )
    public
        attr_accessor   :number, :premises, :conclusions, :cf
        def initialize( number, premises, conclusions, cf )
            raise(ArgumentError, "Invalid certainty factor #{cf}") unless is_cf? cf 
            @number     = number
            @premises   = premises
            @conclusions= conclusions
            @cf         = cf
        end
        
       
        def to_s
            "Rule #{@number}: \n" +
            "    If  " +
            @premises.join("\n        ") + "\n" +
            "    Then with certainty of #{@cf} \n" +
            "        " +
            @conclusions.join("\n        ") 
        end
    end
    
    
    class Rules < Hash
    #
    # Rules are indexed by parameter in each rule conclusion. 
    # If there are two conclusions in a rule, the rule would appear in
    # two elements of the hash.
    #
    public

        def put( rule )
        # Put the rule in a table, indexed under each parm in the conclusion
            rules = self
            rule.conclusions.each {|conclusion|
                if ! rules[ conclusion.param ] then
                    rules[ conclusion.param ] = []
                end
                rules[ conclusion.param ].push rule
            }
        end
        
        def get( param )
        # Returns a list of rules that help determine this parameter
            self[param] ? self[param] : []
        end
        
        def to_s
            str="Hash has #{self.length} elements:\n"
            self.each{|key,value|
                str += "Parameter: #{key}\n"
                str += "Rules:\n"
                str += "    " + value.join("\n    ") + "\n"
            }
            str
        end
    end
    
    
    def add_rule( number, premises, conclusions, cf )
        @rules.put Rule.new( number, premises, conclusions, cf )
    end
    
    def new_premise( str )
    # Creates a new premise/conclusion, 
    # and verifies that each part of it is valid 
    # (e.g. parameter must already be defined)
        Premise.new_from_string( str, @operations, @parameters )
    end
    
    def new_conclusion( str )
        Conclusion.new_from_string( str, @operations, @parameters )
    end
    



    
    class MycinDb < Hash
    #
    # @@db[key] = val
    #     where:key = [paramname, instancename]
    #           val = [ ValueCf(fact,cf), ValueCf(fact,cf) ... ]
    #
        def initialize
            super([])           # if key not found, return empty array [] instead of nil
        end
        
        def get(parm, inst)
            key=[parm,inst]
            self[key]
        end
        def put(parm, inst, val)
            key=[parm,inst]
            self[key] = val
        end
         
        def get_vals(parm, inst)
        # Returns a list of (val cf) pairs
            get(parm, inst)
        end
        
        def get_cf(parm, inst, val)
        # Lookup crtainty factor, or return 'Unknown'
            vals = get_vals(parm, inst)
            if ! vals.empty? then vals.find{|v| v.value==val}.cf
            else Unknown
            end
        end
        
        def update_cf(parm, inst, valcf)
        # Change the certainty factor for (parm inst is val)
        # by combining the given cf with the old
            raise(ArgumentError, "Invalid value-certainty #{val}") unless valcf.kind_of?(ValueCf)
            
            vals = get(parm, inst)
            if ! vals.empty? then
                val = vals.find{|v| v.value == valcf.value}
                if val then
                    val.cf = cf_or(val.cf, valcf.cf)
                else
                    vals.push valcf
                end
            else
                put parm, inst, [valcf]
            end
        end
        
        
        def to_s
            self.collect{|key,vals|
                "#{key[0]},#{key[1]} => [ #{vals.join('; ')} ]\n"
            }.join("\n")
        end
        
    end    
        
    def is_asked? (parm, inst)
        @asked.include? [parm,inst]
    end
    
    def flag_as_asked (parm, inst)
        @asked.push [parm,inst]
    end
    
        
    def get_known(parm, inst)
        key=[parm,inst]
        @known[key]
    end
    def put_known(parm, inst, val)
        key=[parm,inst]
        @known[key] = val
    end
        
        
        
    def put_instance (name, inst)
        @instances[name] = inst
    end
    def get_instance (name)
        @instances[name]
    end
        

        
        
    HELP_STRING = \
    " Type one of the following:
    ?       - to see possible answers for this parameter    
    rule    - to show current rule
    why     - to see why this question is asked
    help    - to see this list
    xxx     - (for some specific xxx) if there is a definite answer
    xxx .5 yyy .4 - if there are several answers with
                different certainty factors
    "
    
    def ask_vals (parm, inst)
    # Ask the user for the value(s) of inst's parm parameter
    # unless this has already been asked. Keep asking until the user
    # types 'unknown' (return nil) or a valid reply (return t).
        unless is_asked?(parm, inst)
            flag_as_asked(parm, inst)
            
            while true
                begin
                    answer = prompt_and_read_vals(parm, inst).downcase
                rescue ArgumentError => err
                    println err
                    next
                end
                case answer
                when "help" then println HELP_STRING
                when "why"  then print_why @current_rule, parm
                when "rule" then println @current_rule
                when "unk","unknown" then return false
                when "?"    then println @parameters.get(parm).type_restriction.help + "\n"
                when "rules" then pdbg "#{@rules}"
                when "db" then pdbg "Database: \n#{@db}"
                else
                    if check_reply(answer, parm, inst)
                    then return true
                    else println "Illegal reply - Type '?' to see legal ones"
                    end
                end
            end
        end
    end
    
    def prompt_and_read_vals (parm, inst)
    # Print the prompt for this parameters (or make one up) 
    # and read the reply
        p = @parameters.get(parm)
        println
        printf(p.prompt, inst.upcase, parm.upcase)
        print " "
        p.reader.call().chop!
    end
    
   
    def check_reply(answer, parm, inst)
    # If reply is valid for this parm, update the dB.
    # Reply should be a "val" or "val1,cf1, val2,cf2 ...".
    # Each type must be of the right type for this parm."
        begin
            val_cf_pairs = parse_reply(answer)
            if val_cf_pairs.every{|pair| 
                @parameters.get(parm).type_restriction.verify( pair.value ) and
                is_cf?( pair.cf )
            } then
                val_cf_pairs.each {|pair| @db.update_cf(parm, inst, pair) }
                true
            else
                false
            end
        rescue Exception => err
            println "Input error: #{err}"
            false
        end
    end
    
    def parse_reply(reply)
    # Convert the reply into an array of [value,cf] pairs
    # Reply is either just a value (e.g. "aerobic")
    # or a list of value-confidence pairs(e.g. "aerobic 0.8  anaerobic 0.2")
    # Returns array of ValueCf, 
    #       e.g. [ ValueCf("aerobic",.8) , ValueCf("anaerobic",.2) ]
        r = reply.split
        if r.empty? then nil
        elsif r.length == 1 then [ValueCf.new( r[0], True )]
        elsif r.length.modulo(2) == 0 then 
            (0..r.length/2-1).collect{|i| ValueCf.new( r[2*i], r[2*i+1].to_f ) }
        else raise ArgumentError, "Odd number of arguments"
        end
    end
    
    def print_why( rule, param )
    # Tell why this rule is being used. Print what is known,
    # what we are trying to find out, and what we can conclude.
        println "[Why is the value of #{param} being asked for?]"
        
        if ["initial", "goal"].member? rule then 
            println "#{param} is one of the #{rule} parameters."
        else
           
            knowns, unknowns = 
                rule.premises.partition_if{|premise|
                    cf_true? eval_condition(premise, ! Call_find_out)
                }
                
                
            if ! knowns.empty? then
                println "It is known that:"
                knowns.each {|known| println "    "+known.to_s }
                println "Therefore, "
            end
            new_rule = rule.clone
            new_rule.premises = unknowns
            println new_rule.to_s
            println
        end
    end


#####################################################################################
#
# Expert System Engine
#
# The calling sequence (note the recursive call to find_out())
#
#   find_out                        # To find out a parameter for an instance:
#       get_known                   #   See if it is cached in the database
#       ask_vals                    #   See if the user knows the answer
#       use_rules                   #   See if there is a rule for it:
#           reject_premise          #       See if the rule is outright false
#           satisfy_premises        #       or see if each condition is true:
#               eval_condition      #           Evalueate each condition
#                   find_out        #               by finding the parameter's values
#
#####################################################################################

    def find_out( param, inst=@current_instance )
    # Find the value(s) of this parameter for this instance
    # unless the values are already known
    # Some parameters we ask first; others we use rules first
    
        get_known(param, inst)   or
        put_known(param, inst, 
            if @parameters.get(param).ask_first   then 
                ( ask_vals(param, inst) or use_rules(param) )
            else
                ( use_rules(param) or ask_vals(param, inst) )
            end
        )

    end

    
    def use_rules(param)
    # Try every rule associated with this parameter.
    # Return true if one of the rules return true."
        @rules.get(param).
            collect{|rule| use_rule(rule)}.
                some{|cf| cf_true? cf}
    end
    
    def use_rule( rule )
    # Apply a rule to the current situation.
    # Return cf (certainty factor)
    # Keep track of the rule for the explanation system:
        @current_rule = rule
    # If any premise is known false, give up.
    # If every premise can be proven true, then
    # draw conclusions (weighted with certainty factors)
        if rule.premises.some {|premise| reject_premise(premise)} then
            return Unknown
        else
            cf = satisfy_premises( rule.premises )
            if cf_true? cf then 
                rule.conclusions.each {|conclusion|
                    conclude conclusion, cf * rule.cf
                }
            end
            return cf
        end  
    end
    
    
    def satisfy_premises( premises, cf_so_far=True)
    # A list of premises is setisfied if they are all true.
    # Combined cf is returned.
        if      premises.empty?     then cf_so_far
        elsif ! cf_true? cf_so_far  then False
        else 
                satisfy_premises(
                    premises[1..-1], 
                    cf_and( cf_so_far, eval_condition(premises[0])) )
        end
    end
    
    def eval_condition( premise, call_find_out = true )
    # See if this condition is true, optionally using find_out()
    # to determing unknown parameters
    # Returns confidence factor
        param,inst,op,val = parse_condition(premise)
        if call_find_out then
            find_out(param,inst)
        end
        # Add up all the (val cf) pairs that satisfy the test
        sum = 0.0
        @db.get_vals(param,inst).each{|val_cf|
            if op.call( val_cf.value, val) then
                sum += val_cf.cf
            end
        }
        sum
    end
    
    def reject_premise( premise )
    # A premise is rejected if it is known false,
    # without needing to call find_out recursively
        cf_false? eval_condition( premise, ! Call_find_out )
    end
    
    def conclude( conclusion, cf )
    # Add a conclusion (with specified certainty factor) to dB.
        parm, inst, op, val = parse_condition(conclusion)
        @db.update_cf(parm, inst, ValueCf.new(val, cf))
    end
  
    def parse_condition( cond )
    # A condition is of the form [param, inst, op, val]
    # So for (age patient is 21), we would return 4 values:
    # ["age", "patient-1", "is", "21"]. where "patient-1" is current patient
#        return cond.param, @dbget(cond.inst), cond.op, cond.val
        return cond.param, get_instance(cond.inst), cond.op, cond.val
    end
    
#####################################################################################


    def run( contexts )
    # An Expert-System shell. Accumulate data for instances of each context,
    # and solve for goals. Then report the findings.
    
        get_context_data contexts
    end
    
    
    def get_context_data( contexts )
    # For each context, create an instance and try to find out required data.
    # Then go to other contexts, depth first,
    # and finally ask if there are other instances of this context.
    
        unless contexts.empty? then
            context = contexts.first              # remove first elem
            inst    = new_instance(context)
            
            @current_rule = "initial" 
            context.initial_data.each{|d| find_out(d) }
            
            @current_rule = "goal" 
            context.goals.each{|d| find_out(d) }
            
            report_findings( context, inst )
            
            get_context_data( contexts[1..-1] )        # recursively
            
            if y_or_n("Is there another #{context.name}?") then
                get_context_data(contexts)
            end
        end
    end
    
    
    
    def report_findings (context, inst)
    # Print findings on each goal for this instance
        if context.goals.length > 0 then
            println "Findings for #{inst.upcase}" # <--- should print inst_name(inst)
            println "    for these goals: #{context.goals.join(', ')}"
            context.goals.each{|goal|
                values = @db.get_vals(goal, inst)
                # If there are any values for this goal
                # print them sorted by certain factor
                print "    #{goal.upcase}: " + 
                    if ! values.empty? then
                        values.clone.sort{|a,b| b.cf <=> a.cf }.
                            collect{|v| v.to_s }.join(", ").upcase
                    else
                        "UNKNOWN"
                    end
                println
            }
            println
        end
    end
    
    def y_or_n(question)
        while true
            print question," "
            answer = readline.chop.downcase
            case answer
            when "yes" then return true
            when "no"  then return false
            else println "Please answer 'yes' or 'no'"
            end
        end
    end
    
end



