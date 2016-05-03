@io.sql
@types.sql
@reader.sql
@printer.sql

CREATE OR REPLACE PACKAGE mal IS

FUNCTION MAIN(args varchar DEFAULT '()') RETURN integer;

END mal;
/

CREATE OR REPLACE PACKAGE BODY mal IS

FUNCTION MAIN(args varchar DEFAULT '()') RETURN integer IS
    M         mem_type;                 -- general mal value memory pool
    H         types.map_entry_table;    -- hashmap memory pool
    TYPE      env_type IS TABLE OF integer INDEX BY varchar2(100);
    repl_env  env_type;
    line      varchar2(4000);

    -- read
    FUNCTION READ(line varchar) RETURN integer IS
    BEGIN
        RETURN reader.read_str(M, H, line);
    END;

    -- eval

    -- forward declarations
    FUNCTION EVAL(ast integer, env env_type) RETURN integer;
    FUNCTION do_core_func(fn integer, args mal_seq_items_type)
        RETURN integer;

    FUNCTION eval_ast(ast integer, env env_type) RETURN integer IS
        i         integer;
        old_seq   mal_seq_items_type;
        new_seq   mal_seq_items_type;
        new_hm    integer;
        old_midx  integer;
        new_midx  integer;
        k         varchar2(256);
    BEGIN
        IF M(ast).type_id = 7 THEN
            RETURN env(TREAT(M(ast) AS mal_str_type).val_str);
        ELSIF M(ast).type_id IN (8,9) THEN
            old_seq := TREAT(M(ast) AS mal_seq_type).val_seq;
            new_seq := mal_seq_items_type();
            new_seq.EXTEND(old_seq.COUNT);
            FOR i IN 1..old_seq.COUNT LOOP
                new_seq(i) := EVAL(old_seq(i), env);
            END LOOP;
            RETURN types.seq(M, M(ast).type_id, new_seq);
        ELSIF M(ast).type_id IN (10) THEN
            new_hm := types.hash_map(M, H, mal_seq_items_type());
            old_midx := TREAT(M(ast) AS mal_map_type).map_idx;
            new_midx := TREAT(M(new_hm) AS mal_map_type).map_idx;

            k := H(old_midx).FIRST();
            WHILE k IS NOT NULL LOOP
                H(new_midx)(k) := EVAL(H(old_midx)(k), env);
                k := H(old_midx).NEXT(k);
            END LOOP;
            RETURN new_hm;
        ELSE
            RETURN ast;
        END IF;
    END;

    FUNCTION EVAL(ast integer, env env_type) RETURN integer IS
        el       integer;
        f        integer;
        args     mal_seq_items_type;
    BEGIN
        IF M(ast).type_id <> 8 THEN
            RETURN eval_ast(ast, env);
        END IF;
        IF types.count(M, ast) = 0 THEN
            RETURN ast; -- empty list just returned
        END IF;

        -- apply
        el := eval_ast(ast, env);
        f := types.first(M, el);
        args := TREAT(M(types.slice(M, el, 1)) AS mal_seq_type).val_seq;
        RETURN do_core_func(f, args);
    END;

    -- print
    FUNCTION PRINT(exp integer) RETURN varchar IS
    BEGIN
        RETURN printer.pr_str(M, H, exp);
    END;

    -- repl
    FUNCTION mal_add(args mal_seq_items_type) RETURN integer IS
    BEGIN
        RETURN types.int(M, TREAT(M(args(1)) AS mal_int_type).val_int +
                            TREAT(M(args(2)) AS mal_int_type).val_int);
    END;

    FUNCTION mal_subtract(args mal_seq_items_type) RETURN integer IS
    BEGIN
        RETURN types.int(M, TREAT(M(args(1)) AS mal_int_type).val_int -
                            TREAT(M(args(2)) AS mal_int_type).val_int);
    END;

    FUNCTION mal_multiply(args mal_seq_items_type) RETURN integer IS
    BEGIN
        RETURN types.int(M, TREAT(M(args(1)) AS mal_int_type).val_int *
                            TREAT(M(args(2)) AS mal_int_type).val_int);
    END;

    FUNCTION mal_divide(args mal_seq_items_type) RETURN integer IS
    BEGIN
        RETURN types.int(M, TREAT(M(args(1)) AS mal_int_type).val_int /
                            TREAT(M(args(2)) AS mal_int_type).val_int);
    END;

    FUNCTION do_core_func(fn integer, args mal_seq_items_type)
        RETURN integer IS
        fname  varchar(100);
    BEGIN
        IF M(fn).type_id <> 11 THEN
            raise_application_error(-20004,
                'Invalid function call', TRUE);
        END IF;

        fname := TREAT(M(fn) AS mal_str_type).val_str;
        CASE
        WHEN fname = '+' THEN RETURN mal_add(args);
        WHEN fname = '-' THEN RETURN mal_subtract(args);
        WHEN fname = '*' THEN RETURN mal_multiply(args);
        WHEN fname = '/' THEN RETURN mal_divide(args);
        ELSE raise_application_error(-20004,
                'Invalid function call', TRUE);
        END CASE;
    END;

    FUNCTION REP(line varchar) RETURN varchar IS
    BEGIN
        RETURN PRINT(EVAL(READ(line), repl_env));
    END;

BEGIN
    -- initialize memory pools
    M := types.mem_new();
    H := types.map_entry_table();

    repl_env('+') := types.func(M, '+');
    repl_env('-') := types.func(M, '-');
    repl_env('*') := types.func(M, '*');
    repl_env('/') := types.func(M, '/');

    WHILE true LOOP
        BEGIN
            line := stream_readline('user> ', 0);
            IF line IS NULL THEN CONTINUE; END IF;
            IF line IS NOT NULL THEN
                stream_writeline(REP(line));
            END IF;

            EXCEPTION WHEN OTHERS THEN
                IF SQLCODE = -20001 THEN  -- io streams closed
                    RETURN 0;
                END IF;
                stream_writeline('Error: ' || SQLERRM);
                stream_writeline(dbms_utility.format_error_backtrace);
        END;
    END LOOP;
END;

END mal;
/
show errors;

quit;
