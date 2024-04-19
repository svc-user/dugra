unit weird;


interface

uses    
    Def
    
    
    
    ;

function oddities; string; override; reintroduce; 

implementation


function oddities; string;
begin

    var mynum: Integer := %10010000;
    var &as: Integer := &0775;
    const biggo = $beef;
    var maddnesS: Integer := &&&&&&&&&&&&&&&&654;

    Result = '[{0000-00000-000000-00000000}]';

end;

end.