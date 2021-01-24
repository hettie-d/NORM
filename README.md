# NORM
 
 NORM stands for No ORM framework. NORM is not a PosgreSQL extention, not a library, and not a set of functions.
 
 NORM is an approach (a technology) which allows object-oriented applications to interact with relational databases
 directly, without involving any ORM. Why do we want to avoid ORM? Because it negatively impacts application performance.
 
 The doc directory of the repo contains the ppt of the presentations from SOFSEM 2020 conference. 
 Please take a look to find out why NORM was developed, and what are the advantages of this approach.
 
 The sql directory contains a working example of how to build PostgreSQL types and functions using NORM technology.

 ## Publications
 
The only published paper on NORM:

 https://link.springer.com/chapter/10.1007%2F978-3-030-38919-2_54
 
 ##  TOC:
 
 * doc directory contains a Power Point presentation from 
 SOFSEM 2020 conference, where NORM was first officially announced. 
 * sql directory contains a working example of NORM usage. 
 * to install an example, run the \_load.all file from the sql directory
 * see file sql\examples.sql for usage examples
 
 ## More on the NORM example
 
 _create_tables.sql_  creates three tables: account, phone and email and some lookiups.
 
 _initial_data_insert.sql_ does exactly what you think it does
 
 _array_transport.sql_ creates an array_transport funcion. That is the only function you need to save for future use, if you want to try the NORM approach in your company.
 
 _account_pkg.sql_  presents the NORM approach. In our approach, we combine the UDT definitions and corresponding functions into one file, which we call
 a _package_, referencing Oracle packages. 
 
 It includes types definitions, _account\_create_ function, _account\_search\_by\_id_ for simple search
 and _account\_search_ for complex search on the combination of criteria. The matching "select" functions
 convert the output into JSON converted to text for data transfer purposes.
 
 Please refer to the presentation to learn why we are doing the transformation as a separate step. 
 
 Finally,the _account_update_  function performs the update of complex object. In addition to update, 
 it can also insert and delete detailed objects. 
 
 Note, that both insert and update functions also return new/modified object(s)
 
 


