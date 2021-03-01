# What is NORM?
 
 NORM stands for No ORM framework. NORM is not a PosgreSQL extention, not a library, and not a set of functions.
 
 NORM is a methodology which allows object-oriented applications to interact with relational databases
 directly, without involving any ORM. Why do we want to avoid ORM? Because it negatively impacts application performance.
 
 This meethodology was developed by [Hettie Dombrovskaya](https://github.com/hettie-d) and [Boris Novikov](https://github.com/bn1206) and was fully impolemented at Braviant Holidings, Chicago IL.

## What's in the repo?

 The purpose of this repo is to provide a working example of the usage of NORM methodology.
 
 ##  TOC:
 
 * The doc directory contains: a list of publications on NORM and a ppt of the  presentation from SOFSEM 2020 conference, where NORM was first officially announced.Take a look to find out why NORM was developed, and what are the advantages of this approach.
 * The sql directory contains a working example of NORM usage. Take a look to see to build PostgreSQL types and functions using NORM technology.
 * To install this example, run the \_load.all file from the sql directory
 * See file sql\examples.sql for usage
 
## Quick Start

Watch the video below from PostgresBuild2020 Conference, online 

[PostgresBuild 2020 recording](https://drive.google.com/file/d/11eO_9_3Oh2G8UlEDD6vvGxCy_vgVWUBg/view?usp=sharing)

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
 
 


