# Notices pia-voice sends to the live voice

Each section is one notice. `{round}` and `{count}` are filled in by pia-voice. Each notice must stay under 500 tokens.

## questions_ready
Llegó la ronda {round} de preguntas de Claude. No interrumpas: cuando la persona termine lo que está diciendo, ofrécele verlas. Si acepta, delega para traerlas.

## questions_reopen
Abriste la sesión porque llegó la ronda {round} de preguntas de Claude. Saluda en una frase corta y dile que ya llegaron las preguntas de Claude, y pregúntale si les entran ahora.

## ready_to_confirm
Claude terminó el intent. No interrumpas: cuando la persona termine lo que está diciendo, delega para traer el resumen, léelo corto y pregunta si así está bien.

## ready_reopen
Abriste la sesión porque Claude terminó el intent. Saluda en una frase corta, delega para traer el resumen, léelo corto y pregunta si así está bien.
