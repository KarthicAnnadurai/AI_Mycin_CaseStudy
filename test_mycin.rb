#!ruby
#
# Written by Zoran Lazarevic
# http://www.cs.columbia.edu/~laza/
# This is free software
#


require_relative "mycin.rb"

#
#            param  context
#            -----  -------
#
#   (defrule 52
#       if  (site   culture         is  blood )
#           (gram   organism        is  neg   )         <--- premise/condition
#           (morphl organism        is  rod   )
#           (burn   patient         is  serious)
#       then 0.4                                        <--- confidence factor (cf)
#           (identity   organism    is  pseudomonas )   <--- conclusion
#   )
#
#  context: patients, cultures, and organisms
#
#

class Member < MemberVerification
end

def main

    db = EMycin.new             # New Empty Mycin database

#
# First define all entities: operations, parameters
#
    db.add_operation("is", proc{|a,b| a == b })

    # verifying procedures passed to parameters
    yes_no      = Member.new(["yes","no"])
    is_number   = ReplyVerification.new( proc{|x,args| x.to_i.to_s == x }, proc{|a| "Must be a number" })
    
    # Parameters for 'patient'
    db.add_parameter("name", "patient", ReplyVerification.new, "Patient's name: ", Ask_First)
    db.add_parameter("sex",  "patient", Member.new(["male","female"]), "Sex: ", Ask_First)
    db.add_parameter("age",  "patient", is_number, "Age: ", Ask_First)
    db.add_parameter("burn", "patient", Member.new(["no","mild","serious"]), 
                "Is %s a burn patient? If so, mild or serious?", Ask_First)
    db.add_parameter("compromised-host",  "patient", yes_no, 
                "Is %s a compromised host? ")
    
    # Parameters for 'culture'
    db.add_parameter("site",     "culture", Member.new(["blood"]), 
                "From what site was specimen %s taken? ", Ask_First)
    db.add_parameter("days-old", "culture", is_number, 
                "How many days ago was this culture (%s) obtained? ", Ask_First)
    
    # Parameters for 'organism'
    db.add_parameter("identity", "organism", 
                Member.new(["pseudomonas","klebsiella","entero","staphylo","bacteroides","strepto"]), 
                "Enter the identity (genus) of %s? ", Ask_First)
    db.add_parameter("gram",     "organism", Member.new(["acid-fast","pos","neg"]), 
                "The gram strain of %s? ", Ask_First)
    db.add_parameter("morphology","organism", Member.new(["rod","coccus"]), 
                "Is %s a rod or coccus? ", Ask_First)
    db.add_parameter("aerobicity","organism", Member.new(["aerobic","anaerobic"]),
                "What is the aerobicity of %s?")
    db.add_parameter("growth-conformation","organism", Member.new(["chains","pairs","clumps"]))
    
#
# Define all the rules
# Rules can use only the terms defined above. This helps eliminate typos.
#
    
    db.add_rule( 52, 
        [   db.new_premise("site culture  is blood"),
            db.new_premise("gram organism is neg"),
            db.new_premise("morphology organism is rod"),
            db.new_premise("burn patient  is serious") ] , 
        [   db.new_conclusion("identity organism is pseudomonas") ] ,
        0.4 )
    db.add_rule( 71, 
        [   db.new_premise("gram organism is pos"),
            db.new_premise("morphology organism is coccus"),
            db.new_premise("growth-conformation organism  is clumps") ] , 
        [   db.new_conclusion("identity organism is staphylo") ] ,
        0.7 )
    db.add_rule( 73, 
        [   db.new_premise("site culture  is blood"),
            db.new_premise("gram organism is neg"),
            db.new_premise("morphology organism is rod"),
            db.new_premise("aerobicity organism is anaerobic") ] , 
        [   db.new_conclusion("identity organism is bacteroides") ] ,
        0.9 )
    db.add_rule( 75, 
        [   db.new_premise("gram organism is neg"),
            db.new_premise("morphology organism is rod"),
            db.new_premise("compromised-host patient   is yes") ] , 
        [   db.new_conclusion("identity organism is pseudomonas") ] ,
        0.6 )
    db.add_rule( 107, 
        [   db.new_premise("gram organism is neg"),
            db.new_premise("morphology organism is rod"),
            db.new_premise("aerobicity organism is aerobic") ] , 
        [   db.new_conclusion("identity organism is entero") ] ,
        0.8 )
    db.add_rule( 165, 
        [   db.new_premise("gram organism is pos"),
            db.new_premise("morphology organism is coccus"),
            db.new_premise("growth-conformation organism  is chains") ] , 
        [   db.new_conclusion("identity organism is strepto") ] ,
        0.7 )

#
# Define which questions should be asked first, and what is the goal
#

    contexts = [
        Context.new("patient", ["name", "sex", "age"]), # Ask about patient 
        Context.new("culture", ["site", "days-old"]),   # ..and the culture
        Context.new("organism", [], ["identity"] )      # Goal is identity of organism
        ]
#
# Now run the expert system. User will be asked questions, thus populating 
# the database
#
    db.run contexts

#
# Done.
#
    db.clear

end




$tracefuncs = ["find_out", "get_known", "aks_vals", "use_rules", "reject_premise",
            "satisfy_premises", "eval_condition"]

class TraceCalls
  def initialize(n)
    @level = n
  end
  def func
    return proc {|event, file, line, id, binding, classname|
      case event
        when "c-call", "call"
          if $tracefuncs.member?(id.to_s) then
              printf("%18s %6d", file, line)
              (2*@level).times do print " " end
              print "call ", classname, ".", id, "\n"
              @level += 1
          end
        when "c-return", "return"
          if $tracefuncs.member?(id.to_s) then
              printf("%18s %6d", file, line)
              @level -= 1
              (2*@level).times do print " " end
              print "exit ", classname, ".", id, "\n"
          end
      end
    }
  end
end

# set_trace_func TraceCalls.new(1).func

main



=begin

#
# This is a result of a test run
# The example is from the book.
#

>test_mycin.rb

------- patient-1 -------

Patient's name:  HELP
 Type one of the following:
    ?       - to see possible answers for this parameter
    rule    - to show current rule
    why     - to see why this question is asked
    help    - to see this list
    xxx     - (for some specific xxx) if there is a definite answer
    xxx .5 yyy .4 - if there are several answers with
                different certainty factors

Patient's name:  SYLVIA_FISHER

Sex:  FEMALE

Age:  27
------- culture-1 -------

From what site was specimen CULTURE-1 taken?  BLOOD

How many days ago was this culture (CULTURE-1) obtained?  3
------- organism-1 -------

Enter the identity (genus) of ORGANISM-1?  UNKNOWN

The gram strain of ORGANISM-1?  ?
Must be one of: acid-fast, pos, neg


The gram strain of ORGANISM-1?  NEG

Is ORGANISM-1 a rod or coccus?  ROD

Is PATIENT-1 a burn patient? If so, mild or serious? WHY
[Why is the value of burn being asked for?]
It is known that:
    The site of the culture is blood
    The gram of the organism is neg
    The morphology of the organism is rod
Therefore,
Rule 52:
    If  The burn of the patient is serious
    Then with certainty of 0.4
        The identity of the organism is pseudomonas


Is PATIENT-1 a burn patient? If so, mild or serious? SERIOUS

What is the aerobicity of ORGANISM-1? AEROBIC

Is PATIENT-1 a compromised host?  YES
Findings for ORGANISM-1
    for these goals: identity
    IDENTITY: ENTERO 0.8, PSEUDOMONAS 0.76

Is there another organism?YES
------- organism-2 -------

Enter the identity (genus) of ORGANISM-2?  UNKNOWN

The gram strain of ORGANISM-2?  NEG 0.8  POS 0.2

Is ORGANISM-2 a rod or coccus?  ROD

What is the aerobicity of ORGANISM-2? ANAEROBIC
Findings for ORGANISM-2
    for these goals: identity
    IDENTITY: BACTEROIDES 0.72, PSEUDOMONAS 0.6464

Is there another organism?NO
Is there another culture?NO
Is there another patient?NO

=end
